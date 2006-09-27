/* Mark objects as 'ancient' so they are taken out of the OCaml heap.
 * $Id: ancient_c.c,v 1.2 2006-09-27 14:05:07 rich Exp $
 */

#include <string.h>
#include <assert.h>

#include <caml/config.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/mlvalues.h>
#include <caml/fail.h>

// From byterun/misc.h:
typedef char * addr;

// From byterun/minor_gc.c:
CAMLextern char *caml_young_start;
CAMLextern char *caml_young_end;
#define Is_young(val) \
  (assert (Is_block (val)),						\
   (addr)(val) < (addr)caml_young_end && (addr)(val) > (addr)caml_young_start)

// From byterun/major_gc.h:
#ifdef __alpha
typedef int page_table_entry;
#else
typedef char page_table_entry;
#endif
CAMLextern char *caml_heap_start;
CAMLextern char *caml_heap_end;
CAMLextern page_table_entry *caml_page_table;
extern asize_t caml_page_low, caml_page_high;

#define In_heap 1
#define Not_in_heap 0
#define Page(p) ((uintnat) (p) >> Page_log)
#define Is_in_heap(p) \
  (assert (Is_block ((value) (p))),					\
   (addr)(p) >= (addr)caml_heap_start && (addr)(p) < (addr)caml_heap_end \
   && caml_page_table [Page (p)])

// Area is an expandable buffer, allocated on the C heap.
typedef struct area {
  void *ptr;			// Start of area.
  size_t n;			// Current position.
  size_t size;			// Allocated size.
} area;

static inline void
area_init (area *a)
{
  a->ptr = 0;
  a->n =
  a->size = 0;
}

static inline int
area_append (area *a, const void *obj, size_t size)
{
  while (a->n + size > a->size) {
    if (a->size == 0) a->size = 256; else a->size <<= 1;
    a->ptr = realloc (a->ptr, a->size);
    if (a->ptr == 0) return -1; // Out of memory.
  }
  memcpy (a->ptr + a->n, obj, size);
  a->n += size;
  return 0;
}

static inline void
area_shrink (area *a)
{
  if (a->n != a->size) {
    a->size = a->n;
    a->ptr = realloc (a->ptr, a->size);
    assert (a->ptr); // Getting smaller, so shouldn't really fail.
  }
}

static inline void
area_free (area *a)
{
  free (a->ptr);
  a->n =
  a->size = 0;
}

struct restore_item {
  char *header;
  value field_zero;
};

// When a block is visited, we overwrite the header with all 1's.
// This is not quite an impossible value - one could imagine an
// enormous custom block where the header could take on this
// value. (XXX)
static header_t visited = (unsigned long) -1;

// The general plan here:
//
// 1. Starting at [obj], copy it to our out-of-heap memory area
// defined by [ptr].
// 2. Recursively visit subnodes of [obj] and do the same.
// 3. As we copy each object, we avoid circularity by setting that
// object's header to a special 'visited' value.  However since these
// are objects in the Caml heap we have to restore the original
// headers at the end, which is the purpose of the [restore] area.
// 4. We use realloc to allocate the memory for the copy, but because
// the memory can move around, we cannot store absolute pointers.
// Instead we store offsets and fix them up later.  This is the
// purpose of the [fixups] area.
//
// XXX Large, deeply recursive structures cause a stack overflow.
// Temporary solution: 'ulimit -s unlimited'.  This function should
// be replaced with something iterative.
static size_t
mark (value obj, area *ptr, area *restore, area *fixups)
{
  char *header = Hp_val (obj);
  assert (Wosize_hp (header) > 0); // Always true? (XXX)

  // We can't handle out-of-heap objects.
  // XXX Since someone might try to mark an ancient object, they
  // might get this error, so we should try to do better here.
  assert (Is_young (obj) || Is_in_heap (obj));

  // If we've already visited this object, just return its offset
  // in the out-of-heap memory.
  if (memcmp (header, &visited, sizeof visited) == 0)
    return (Long_val (Field (obj, 0)));

  // Offset where we will store this object in the out-of-heap memory.
  size_t offset = ptr->n;

  // Copy the object out of the OCaml heap.
  size_t bytes = Bhsize_hp (header);
  if (area_append (ptr, header, bytes) == -1)
    return -1;			// Error out of memory.

  // Scan the fields looking for pointers to blocks.
  int can_scan = Tag_val (obj) < No_scan_tag;
  if (can_scan) {
    mlsize_t nr_words = Wosize_hp (header);
    mlsize_t i;

    for (i = 0; i < nr_words; ++i) {
      value field = Field (obj, i);

      if (Is_block (field) &&
	  (Is_young (field) || Is_in_heap (field))) {
	size_t field_offset = mark (field, ptr, restore, fixups);
	if (field_offset == -1) return -1; // Propagate out of memory errors.

	// Since the recursive call to mark above can reallocate the
	// area, we need to recompute these each time round the loop.
	char *obj_copy_header = ptr->ptr + offset;
	value obj_copy = Val_hp (obj_copy_header);

	// Don't store absolute pointers yet because realloc will
	// move the memory around.  Store a fake pointer instead.
	// We'll fix up these fake pointers afterwards.
	Field (obj_copy, i) = field_offset + sizeof (header_t);

	size_t fixup = (void *)&Field(obj_copy, i) - ptr->ptr;
	area_append (fixups, &fixup, sizeof fixup);
      }
    }
  }

  // Mark this object as having been "visited", but keep track of
  // what was there before so it can be restored.  We also need to
  // record the offset.
  // Observations:
  // (1) What was in the header before is kept in the out-of-heap
  // copy, so we don't explicitly need to remember that.
  // (2) We can keep the offset in the zeroth field, but since
  // the code above might have modified the copy, we need to remember
  // what was in that field before.
  // (3) We can overwrite the header with all 1's to indicate that
  // we've visited (but see notes on 'static header_t visited' above).
  // (4) All objects in OCaml are at least one word long (we hope!).
  struct restore_item restore_item;
  restore_item.header = header;
  restore_item.field_zero = Field (obj, 0);
  area_append (restore, &restore_item, sizeof restore_item);

  memcpy (header, (void *)&visited, sizeof visited);
  Field (obj, 0) = Val_long (offset);

  return offset;
}

// See comments immediately above.
static void
do_restore (area *ptr, area *restore)
{
  mlsize_t i;
  for (i = 0; i < restore->n; i += sizeof (struct restore_item))
    {
      struct restore_item *restore_item =
	(struct restore_item *)(restore->ptr + i);
      assert (memcmp (restore_item->header, &visited, sizeof visited) == 0);

      value obj = Val_hp (restore_item->header);
      size_t offset = Long_val (Field (obj, 0));

      char *obj_copy_header = ptr->ptr + offset;
      //value obj_copy = Val_hp (obj_copy_header);

      // Restore the original header.
      memcpy (restore_item->header, obj_copy_header, sizeof visited);

      // Restore the original zeroth field.
      Field (obj, 0) = restore_item->field_zero;
    }
}

// Fixup fake pointers.
static void
do_fixups (area *ptr, area *fixups)
{
  long i;

  for (i = 0; i < fixups->n; i += sizeof (size_t))
    {
      size_t fixup = *(size_t *)(fixups->ptr + i);
      size_t offset = *(size_t *)(ptr->ptr + fixup);
      void *real_ptr = ptr->ptr + offset;
      *(value *)(ptr->ptr + fixup) = (value) real_ptr;
    }
}

CAMLprim value
ancient_mark (value obj)
{
  CAMLparam1 (obj);
  CAMLlocal1 (proxy);

  area ptr; // This will be the out of heap area.
  area_init (&ptr);
  area restore; // Headers to be fixed up after.
  area_init (&restore);
  area fixups; // List of fake pointers to be fixed up.
  area_init (&fixups);

  if (mark (obj, &ptr, &restore, &fixups) == -1) {
    // Ran out of memory.  Recover and throw an exception.
    do_restore (&ptr, &restore);
    area_free (&fixups);
    area_free (&restore);
    area_free (&ptr);
    caml_failwith ("out of memory");
  }
  area_shrink (&ptr);

  // Restore Caml heap structures.
  do_restore (&ptr, &restore);
  area_free (&restore);

  // Update all fake pointers in the out of heap area to make them real
  // pointers.
  do_fixups (&ptr, &fixups);
  area_free (&fixups);

  // Replace obj with a proxy.
  proxy = caml_alloc (1, Abstract_tag);
  Field (proxy, 0) = (value) ptr.ptr;

  CAMLreturn (proxy);
}

CAMLprim value
ancient_follow (value obj)
{
  CAMLparam1 (obj);
  CAMLlocal1 (v);

  v = Field (obj, 0);
  if (Is_long (v)) caml_invalid_argument ("deleted");
  v = Val_hp (v); // v points to the header; make it point to the object.

  CAMLreturn (v);
}

CAMLprim value
ancient_delete (value obj)
{
  CAMLparam1 (obj);
  CAMLlocal1 (v);

  v = Field (obj, 0);
  if (Is_long (v)) caml_invalid_argument ("deleted");

  // Otherwise v is a pointer to the out of heap malloc'd object.
  assert (!Is_young (v) && !Is_in_heap (v));
  free ((void *) v);

  // Replace the proxy (a pointer) with an int 0 so we know it's
  // been deleted in future.
  Field (obj, 0) = Val_long (0);

  CAMLreturn (Val_unit);
}
