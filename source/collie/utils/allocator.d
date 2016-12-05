﻿module collie.utils.allocator;

import core.memory;
import std.traits;
import std.experimental.allocator.common;

struct CollieAllocator(T)
{
	enum uint alignment = platformAlignment;
	enum TInfo = typeid(T[]);

	static if(hasIndirections!T){
		enum uint blkAttr = 0;
	} else {
		enum uint blkAttr = GC.BlkAttr.NO_SCAN;
	}

	pure nothrow @trusted void[] allocate(size_t bytes) shared
	in{
		assert((bytes % T.sizeof) == 0);
	}body{
		if (!bytes) return null;
		auto p = GC.malloc(bytes,blkAttr,TInfo);
		return p ? p[0 .. bytes] : null;
	}

	@system bool expand(ref void[] b, size_t delta) shared
	in{
		assert((delta % T.sizeof) == 0);
	}body{
		if (delta == 0) return true;
		if (b is null) return false;
		immutable curLength = GC.sizeOf(b.ptr);
		assert(curLength != 0); // we have a valid GC pointer here
		immutable desired = b.length + delta;
		if (desired > curLength) // check to see if the current block can't hold the data
		{
			immutable sizeRequest = desired - curLength;
			immutable newSize = GC.extend(b.ptr, sizeRequest, sizeRequest,TInfo);
			if (newSize == 0)
			{
				// expansion unsuccessful
				return false;
			}
			assert(newSize >= desired);
		}
		b = b.ptr[0 .. desired];
		return true;
	}

	pure nothrow @system bool reallocate(ref void[] b, size_t newSize) shared
	in{
		assert((newSize % T.sizeof) == 0);
	}body{
		import core.exception : OutOfMemoryError;
		try
		{
			auto p = cast(ubyte*) GC.realloc(b.ptr, newSize,blkAttr,TInfo);
			b = p[0 .. newSize];
		}
		catch (OutOfMemoryError)
		{
			// leave the block in place, tell caller
			return false;
		}
		return true;
	}

	pure nothrow void[] resolveInternalPointer(void* p) shared
	{
		auto r = GC.addrOf(p);
		if (!r) return null;
		return r[0 .. GC.sizeOf(r)];
	}

	pure nothrow @system bool deallocate(void[] b) shared
	{
		GC.free(b.ptr);
		return true;
	}

	static shared CollieAllocator!T instance;

	nothrow @trusted void collect() shared
	{
		GC.collect();
	}
}

///
unittest
{
	auto buffer = CollieAllocator!int.instance.allocate(1024 * 1024 * 4);
	// deallocate upon scope's end (alternatively: leave it to collection)
	scope(exit) CollieAllocator!int.instance.deallocate(buffer);
	//...
}

unittest
{
	auto b = CollieAllocator!int.instance.allocate(10_000);
	assert(CollieAllocator!int.instance.expand(b, 1));
}

unittest
{
	import core.memory : GC;
	
	// test allocation sizes
	assert(CollieAllocator!int.instance.goodAllocSize(1) == 16);
	for (size_t s = 16; s <= 8192; s *= 2)
	{
		assert(CollieAllocator!int.instance.goodAllocSize(s) == s);
		assert(CollieAllocator!int.instance.goodAllocSize(s - (s / 2) + 1) == s);
		
		auto buffer = CollieAllocator!int.instance.allocate(s);
		scope(exit) CollieAllocator!int.instance.deallocate(buffer);
		
		assert(GC.sizeOf(buffer.ptr) == s);
		
		auto buffer2 = CollieAllocator!int.instance.allocate(s - (s / 2) + 1);
		scope(exit) CollieAllocator!int.instance.deallocate(buffer2);
		
		assert(GC.sizeOf(buffer2.ptr) == s);
	}
	
	// anything above a page is simply rounded up to next page
	assert(CollieAllocator!int.instance.goodAllocSize(4096 * 4 + 1) == 4096 * 5);
}