package.cpath = "bin/?.dll"

local iup = require "iuplua"
local bgfx = require "bgfx"
local util = require "util"
local math3d = require "math3d"

local ctx = {
	canvas = iup.canvas {},
}

local dlg = iup.dialog {
	ctx.canvas,
	title = "03-raymarch",
	size = "HALFxHALF",
}

local index = { 0,2,1,0,3,2 }

local function renderScreenSpaceQuad(minx, miny, width, height)
	ctx.tb:alloc(4, 6, ctx.vdecl)
	local zz = 0
	local maxx = minx + width
	local maxy = miny + height
	local minu = -1.0
	local minv = -1.0
	local maxu = 1
	local maxv = 1

	ctx.tb:packV(0, minx, miny, zz, 0xff0000ff, minu, minv)
	ctx.tb:packV(1, maxx, miny, zz, 0xff00ff00, maxu, minv)
	ctx.tb:packV(2, maxx, maxy, zz, 0xffff0000, maxu, maxv)
	ctx.tb:packV(3, minx, maxy, zz, 0xffffffff, minu, maxv)

	ctx.tb:packI(index)
	bgfx.set_state()	-- default
	ctx.tb:set()
	bgfx.submit(1, ctx.prog)
end

local time = 0
local function mainloop()
	math3d.reset()
	bgfx.touch(0)
	time = time + 0.01

	local vp = math3d.mul(ctx.projmat, ctx.viewmat)
	local mtx = math3d.matrix { r = { time , time * 0.37, 0 } }
	local lightDirModelN = math3d.normalize(math3d.vector (-0.4, -0.5, -1.0))
	local lightDirTime = math3d.transform(math3d.inverse(mtx) , lightDirModelN, 0)

	bgfx.set_uniform(ctx.u_lightDirTime, math3d.vector(lightDirTime, time)) --	lightDirTime[4] = time
--	local command = bgfx.set_uniform_command(ctx.u_lightDirTime, math3d.vector(lightDirTime, time))
	local invMvp = math3d.inverse(math3d.mul(vp, mtx))
	bgfx.set_uniform(ctx.u_mtx, invMvp)
--	command = command .. bgfx.set_uniform_command(ctx.u_mtx, invMvp)
--	bgfx.execute_setter(command)

	renderScreenSpaceQuad(0.0, 0.0, 1280.0, 720.0)

	bgfx.frame()
end

function ctx.init()
	bgfx.set_view_clear(0, "CD", 0x303030ff, 1, 0)

	ctx.prog = util.programLoad("vs_raymarching", "fs_raymarching")
	ctx.vdecl = bgfx.vertex_layout {
		{ "POSITION", 3, "FLOAT" },
		{ "COLOR0", 4, "UINT8", true },
		{ "TEXCOORD0", 2, "FLOAT" },
	}
	ctx.u_mtx = bgfx.create_uniform("u_mtx", "m4")
	ctx.u_lightDirTime = bgfx.create_uniform("u_lightDirTime", "v4")
	ctx.tb = bgfx.transient_buffer "fffdff"
	ctx.viewmat = math3d.ref(math3d.matrix())
	ctx.projmat = math3d.ref(math3d.matrix())
end

function ctx.resize(w,h)
	ctx.width = w
	ctx.height = h
	bgfx.set_view_rect(0, 0, 0, w, h)
	bgfx.set_view_rect(1, 0, 0, w, h)
	bgfx.reset(w,h, "v")

	ctx.viewmat.mat = math3d.lookat( {0,0,-15}, {0, 0, 0} )
	ctx.projmat.mat = math3d.projmat { fov = 60, aspect = w/h , n = 0.1, f = 100 }
	bgfx.set_view_transform(0, ctx.viewmat, ctx.projmat)
	local orthomat = math3d.projmat { ortho = true, l = 0.0, r= 1280.0, b = 720.0, t = 0.0, n = 0.0, f = 100.0 }
	bgfx.set_view_transform(1, nil, orthomat)
end

util.init(ctx)
dlg:showxy(iup.CENTER,iup.CENTER)
dlg.usersize = nil
util.run(mainloop)

--bgfx.destroy(ctx.prog)
--bgfx.destroy(ctx.u_mtx)
--bgfx.destroy(ctx.u_lightDirTime)
