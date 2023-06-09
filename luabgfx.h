#ifndef lua_bgfx_h
#define lua_bgfx_h

#include <stdint.h>

enum BGFX_HANDLE {
	BGFX_HANDLE_PROGRAM = 1,
	BGFX_HANDLE_SHADER,
	BGFX_HANDLE_VERTEX_BUFFER,
	BGFX_HANDLE_INDEX_BUFFER,
	BGFX_HANDLE_DYNAMIC_VERTEX_BUFFER,
	BGFX_HANDLE_DYNAMIC_VERTEX_BUFFER_TYPELESS,
	BGFX_HANDLE_DYNAMIC_INDEX_BUFFER,
	BGFX_HANDLE_DYNAMIC_INDEX_BUFFER_32,
	BGFX_HANDLE_FRAME_BUFFER,
	BGFX_HANDLE_INDIRECT_BUFFER,
	BGFX_HANDLE_TEXTURE,
	BGFX_HANDLE_UNIFORM,
	BGFX_HANDLE_OCCLUSION_QUERY,
};

#define BGFX_LUAHANDLE(type, handle) (BGFX_HANDLE_##type << 16 | handle.idx)
#define BGFX_LUAHANDLE_ID(type, idx) check_handle_type(L, BGFX_HANDLE_##type, (idx), #type)
#define BGFX_LUAHANDLE_WITHTYPE(idx, subtype) ( (idx) | (subtype) << 20 )
#define BGFX_LUAHANDLE_SUBTYPE(idx) ( (idx) >> 20 )

static inline uint16_t
check_handle_type(lua_State *L, int type, int id, const char * tname) {
	int idtype = (id >> 16) & 0x0f;
	if (idtype != type) {
		return luaL_error(L, "Invalid handle type %s (id = %d:%d)", tname, idtype, id&0xffff);
	}
	return (uint16_t)(id & 0xffff);
}

struct memory {
	void *data;
	size_t size;
	int ref;
	int constant;
};

#if LUA_VERSION_NUM < 504
// lua 5.3

static inline void *
lua_newuserdatauv(lua_State *L, size_t size, int nuvalue) {
	if (nuvalue > 1)
		luaL_error(L, "Don't support nuvalue (%d) > 1", nuvalue);
	return lua_newuserdata(L, size);
}

static inline int
lua_setiuservalue(lua_State *L, int idx, int n) {
	if (n != 1)
		return luaL_error(L, "Don't support setiuservalue %d !=1", n);
	return lua_setuservalue(L, idx);
}

#endif

#endif
