/* Mark objects as 'ancient' so they are taken out of the OCaml heap.
 */

#include <string.h>
#include <assert.h>

#define CAML_INTERNALS

#include <caml/config.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/mlvalues.h>
#include <caml/fail.h>
#include <caml/address_class.h>

#if OCAML_VERSION_MAJOR == 5
#include <caml/shared_heap.h>
#define Ancient_blackhd_hd(hd) With_status_hd (hd, NOT_MARKABLE)
#else
#define Ancient_blackhd_hd(hd) Blackhd_hd(hd)

#endif

#include "mmalloc/mmalloc.h"

// Area is an expandable buffer, allocated on the C heap.
typedef struct area {
  void *ptr;			// Start of area.
  size_t n;			// Current position.
  size_t size;			// Allocated size.

  // If this area requires custom realloc function, these will be non-null.
  void *(*realloc)(void *data, void *ptr, size_t size);
  void (*free)(void *data, void *ptr);
  void *data;
} area;

static inline void
area_init (area *a)
{
  a->ptr = 0;
  a->n =
  a->size = 0;
  a->realloc = 0;
  a->free = 0;
  a->data = 0;
}

static inline void
area_init_custom (area *a,
		  void *(*realloc)(void *data, void *ptr, size_t size),
		  void (*free)(void *data, void *ptr),
		  void *data)
{
  area_init (a);
  a->realloc = realloc;
  a->free = free;
  a->data = data;
}

static inline int
area_append (area *a, const void *obj, size_t size)
{
  void *ptr;
  while (a->n + size > a->size) {
    if (a->size == 0) a->size = 256; else a->size <<= 1;
    ptr =
      a->realloc
      ? a->realloc (a->data, a->ptr, a->size)
      : realloc (a->ptr, a->size);
    if (ptr == 0) return -1; // Out of memory.
    a->ptr = ptr;
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
    a->ptr =
      a->realloc
      ? a->realloc (a->data, a->ptr, a->size)
      : realloc (a->ptr, a->size);
    assert (a->ptr); // Getting smaller, so shouldn't really fail.
  }
}

static inline void
area_free (area *a)
{
  if (a->free) a->free (a->data, a->ptr);
  else free (a->ptr);
  a->n =
  a->size = 0;
}

struct restore_item {
  header_t *header_ptr;
  value field_zero;
};

/* When a block is visited, we set its tag to Double_tag, and its
 * wosize to 10. This header is impossible to generate in a classical
 * OCaml runtime (idea by Damien Doligez)
 */

#define ATOM_OFFSET 10
static header_t visited = Make_header(10, Double_tag, 0);
static value atoms[256];

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

/*
 * obj: source object
 * ptr: destination
 * restore: a list of pointers that we modified that we should restore
   at the end of the marking
 * fixups: a list of pointers that we have created that we may need to
   update if we realloc the destination
 */

static size_t
_mark (value obj, area *ptr, area *restore, area *fixups)
{
  // XXX This assertion might fail if someone tries to mark an object
  // which is already ancient.
  assert (Is_in_value_area (obj));

  header_t *header_ptr = (header_t *) Hp_val (obj);
  header_t hd = Hd_hp (header_ptr);

  // If we've already visited this object, just return its offset
  // in the out-of-heap memory.
  if ( hd == visited )
    return (Long_val (Field (obj, 0)));

  int wosize = Wosize_hd (hd);
  int tag = Tag_hd (hd);

  /* block is of size 0, and the corresponding atom was already
   * allocated, we don't need to do anything */
  if ( wosize == 0 && atoms[tag] != 0){
	  return atoms[tag] - ATOM_OFFSET;
  }

  // Offset where we will store this object in the out-of-heap memory.
  size_t offset = ptr->n;

  // Copy the object out of the OCaml heap.
  size_t bytes = Bhsize_wosize (wosize);
  if (area_append (ptr, header_ptr, bytes) == -1)
    return -1;			// Error out of memory.

  if ( wosize == 0 ){
	  atoms[tag] = offset + ATOM_OFFSET ;
	  Hd_hp (ptr->ptr+offset) = Ancient_blackhd_hd (hd);
	  return offset ;
  }

  // Scan the fields looking for pointers to blocks.
  int can_scan = tag < No_scan_tag;
  if (can_scan) {
    mlsize_t i;

    for (i = 0; i < wosize; ++i) {
	    value field = Field (obj, i);

	    if (Is_block (field) && Is_in_value_area (field)){
		    size_t field_offset =
			    _mark (field, ptr, restore, fixups);
		    // Propagate out of memory errors.
		    if (field_offset == -1) return -1;

		    // Since the recursive call to mark above can
		    // reallocate the area, we need to recompute these
		    // each time round the loop.
		    char *obj_copy_header = ptr->ptr + offset;
		    value obj_copy = Val_hp (obj_copy_header);

		    // Don't store absolute pointers yet because
		    // realloc will move the memory around.  Store a
		    // fake pointer instead.  We'll fix up these fake
		    // pointers afterwards in do_fixups.
		    Field (obj_copy, i) =
			    field_offset + sizeof (header_t);

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
  // (4) All objects in OCaml are at least one word long (XXX - actually
  // this is not true).
  struct restore_item restore_item;

  restore_item.header_ptr = header_ptr;
  restore_item.field_zero = Field (obj, 0);
  area_append (restore, &restore_item, sizeof restore_item);

  Hd_hp (header_ptr) = visited;
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

      assert ( Hd_hp (restore_item->header_ptr) == visited );

      value obj = Val_hp (restore_item->header_ptr);
      size_t offset = Long_val (Field (obj, 0));

      char *obj_copy_header = ptr->ptr + offset;
      //value obj_copy = Val_hp (obj_copy_header);

      // Restore the original header
      header_t hd = Hd_hp (obj_copy_header);
      Hd_hp (restore_item->header_ptr) = hd;

      // Color the destination header in black
      Hd_hp (obj_copy_header) = Ancient_blackhd_hd (hd);

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

static void *
mark (value obj,
      void *(*realloc)(void *data, void *ptr, size_t size),
      void (*free)(void *data, void *ptr),
      void *data,
      size_t *r_size)
{
	int i;

  area ptr; // This will be the out of heap area.
  area_init_custom (&ptr, realloc, free, data);
  area restore; // Headers to be fixed up after.
  area_init (&restore);
  area fixups; // List of fake pointers to be fixed up.
  area_init (&fixups);

  /* reset atoms */
  for (i=0; i<256; i++){
	  atoms[i] = 0;
  }

  if (_mark (obj, &ptr, &restore, &fixups) == -1) {
    // Ran out of memory.  Recover and throw an exception.
    area_free (&fixups);
    do_restore (&ptr, &restore);
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

  if (r_size) *r_size = ptr.size;
  return ptr.ptr;
}

static void *
my_realloc (void *data __attribute__((unused)), void *ptr, size_t size)
{
  return realloc (ptr, size);
}

static void
my_free (void *data __attribute__((unused)), void *ptr)
{
  return free (ptr);
}

CAMLprim value
ancient_mark_info (value obj)
{
  CAMLparam1 (obj);
  CAMLlocal3 (proxy, info, rv);

  size_t size;
  void *ptr = mark (obj, my_realloc, my_free, 0, &size);

  // Make the proxy.
  proxy = caml_alloc (1, Abstract_tag);
  Field (proxy, 0) = (value) ptr;

  // Make the info struct.
  info = caml_alloc (1, 0);
  Field (info, 0) = Val_long (size);

  rv = caml_alloc (2, 0);
  Field (rv, 0) = proxy;
  Field (rv, 1) = info;

  CAMLreturn (rv);
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
  assert (!Is_in_heap_or_young (v));
  free ((void *) v);

  // Replace the proxy (a pointer) with an int 0 so we know it's
  // been deleted in future.
  Field (obj, 0) = Val_long (0);

  CAMLreturn (Val_unit);
}

CAMLprim value
ancient_is_ancient (value obj)
{
  CAMLparam1 (obj);
  CAMLlocal1 (v);

  v = Is_in_heap_or_young (obj) ? Val_false : Val_true;

  CAMLreturn (v);
}

CAMLprim value
ancient_address_of (value obj)
{
  CAMLparam1 (obj);
  CAMLlocal1 (v);

  if (Is_block (obj)) v = caml_copy_nativeint ((intnat) obj);
  else v = caml_copy_nativeint (0);

  CAMLreturn (v);
}

CAMLprim value
ancient_attach (value fdv, value baseaddrv)
{
  CAMLparam2 (fdv, baseaddrv);
  CAMLlocal1 (mdv);

  int fd = Int_val (fdv);
  void *baseaddr = (void *) Nativeint_val (baseaddrv);
  void *md = mmalloc_attach (fd, baseaddr);
  if (md == 0) {
    perror ("mmalloc_attach");
    caml_failwith ("mmalloc_attach");
  }

  mdv = caml_alloc (1, Abstract_tag);
  Field (mdv, 0) = (value) md;

  CAMLreturn (mdv);
}

CAMLprim value
ancient_detach (value mdv)
{
  CAMLparam1 (mdv);

  void *md = (void *) Field (mdv, 0);

  if (mmalloc_detach (md) != 0) {
    perror ("mmalloc_detach");
    caml_failwith ("mmalloc_detach");
  }

  CAMLreturn (Val_unit);
}

struct keytable {
  void **keys;
  int allocated;
};

CAMLprim value
ancient_share_info (value mdv, value keyv, value obj)
{
  CAMLparam3 (mdv, keyv, obj);
  CAMLlocal3 (proxy, info, rv);

  void *md = (void *) Field (mdv, 0);
  int key = Int_val (keyv);

  // Get the key table.
  struct keytable *keytable = mmalloc_getkey (md, 0);
  if (keytable == 0) {
    keytable = mmalloc (md, sizeof (struct keytable));
    if (keytable == 0) caml_failwith ("out of memory");
    keytable->keys = 0;
    keytable->allocated = 0;
    mmalloc_setkey (md, 0, keytable);
  }

  // Existing key exists?  Free it.
  if (key < keytable->allocated && keytable->keys[key] != 0) {
    mfree (md, keytable->keys[key]);
    keytable->keys[key] = 0;
  }

  // Keytable large enough?  If not, realloc it.
  if (key >= keytable->allocated) {
    int allocated = keytable->allocated == 0 ? 32 : keytable->allocated * 2;
    void **keys = mrealloc (md, keytable->keys, allocated * sizeof (void *));
    if (keys == 0) caml_failwith ("out of memory");
    int i;
    for (i = keytable->allocated; i < allocated; ++i) keys[i] = 0;
    keytable->keys = keys;
    keytable->allocated = allocated;
  }

  // Do the mark.
  size_t size;
  void *ptr = mark (obj, mrealloc, mfree, md, &size);

  // Add the key to the keytable.
  keytable->keys[key] = ptr;

  // Make the proxy.
  proxy = caml_alloc (1, Abstract_tag);
  Field (proxy, 0) = (value) ptr;

  // Make the info struct.
  info = caml_alloc (1, 0);
  Field (info, 0) = Val_long (size);

  rv = caml_alloc (2, 0);
  Field (rv, 0) = proxy;
  Field (rv, 1) = info;

  CAMLreturn (rv);
}

CAMLprim value
ancient_get (value mdv, value keyv)
{
  CAMLparam2 (mdv, keyv);
  CAMLlocal1 (proxy);

  void *md = (void *) Field (mdv, 0);
  int key = Int_val (keyv);

  // Key exists?
  struct keytable *keytable = mmalloc_getkey (md, 0);
  if (keytable == 0 || key >= keytable->allocated || keytable->keys[key] == 0)
    caml_raise_not_found ();
  void *ptr = keytable->keys[key];

  // Return the proxy.
  proxy = caml_alloc (1, Abstract_tag);
  Field (proxy, 0) = (value) ptr;

  CAMLreturn (proxy);
}
