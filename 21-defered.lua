package.cpath = "bin/?.dll"

local iup = require "iuplua"
local bgfx = require "bgfx"
local bgfxu = require "bgfx.util"
local util = require "util"
local math3d = require "math3d"

local ctx = {
	canvas = iup.canvas {},
}

local settings = {
	numLights = 512,
	showGBuffer = true,
	showScissorRects = false,
	animateMesh = true,
	lightAnimationSpeed = 0.3,
}

local function slider(key, title, min, max)
	local value = assert(settings[key])
	local integer = math.type(value) == "integer"
	local tv = value
	local label = iup.label { title = tv , size = "30" }
	local val = iup.val {
		min = min,
		max = max,
		value = value,
		valuechanged_cb = function (self)
			local v = tonumber(self.value)
			if integer then
				v = math.floor(v)
				settings[key] = v
				label.title = string.format("%d",v)
			else
				settings[key] = v
				label.title = string.format("%.2f",v)
			end
		end,
	}

	return iup.hbox {
		iup.label { title = title .. " : " },
		val,
		label,
	}
end

local function checkbox(key, title, func)
	local value = settings[key]
	assert(type(value) == "boolean")
	if func then
		func(value)
	end
	return iup.toggle {
		title = title,
		value = value and "ON" or "OFF",
		action = function (_, v)
			settings[key] = (v == 1)
			if func then
				func(v==1)
			end
		end
	}
end

local ctrl = iup.frame {
	iup.vbox {
		slider("numLights", "Num lights", 1, 2048),
		checkbox("showGBuffer", "Show G-Buffer."),
		checkbox("showScissorRects", "Show light scissor."),
		checkbox("animateMesh", "Animate mesh."),
		slider("lightAnimationSpeed", "lightAnimationSpeed", 0, 0.4),
	},
	title = "Settings",
}

local dlg = iup.dialog {
	iup.hbox {
		iup.vbox {
			ctrl,
			margin = "10x10",
		},
		ctx.canvas,
	},
  title = "21-defered",
  size = "HALFxHALF",
}

local RENDER_PASS_GEOMETRY_ID      = 0
local RENDER_PASS_LIGHT_ID         = 1
local RENDER_PASS_COMBINE_ID       = 2
local RENDER_PASS_DEBUG_LIGHTS_ID  = 3
local RENDER_PASS_DEBUG_GBUFFER_ID = 4

local function screenSpaceQuad(textureWidth, textureHeight, texelHalf, originBottomLeft)
	local width = 1
	local height = 1
	ctx.screen_tb:alloc(3, ctx.PosTexCoord0Vertex)

	local minx = -width
	local maxx =  width
	local miny = 0
	local maxy = height*2

	local texelHalfW = texelHalf/textureWidth
	local texelHalfH = texelHalf/textureHeight
	local minu = -1 + texelHalfW
	local maxu =  1 + texelHalfH

	local zz = 0.0

	local minv = texelHalfH
	local maxv = 2 + texelHalfH

	if originBottomLeft then
		minv, maxv = maxv, minv
		minv = minv - 1
		maxv = maxv - 1
	end

	ctx.screen_tb:packV(0, minx, miny,zz, minu, minv)
	ctx.screen_tb:packV(1, maxx, miny,zz, maxu, minv)
	ctx.screen_tb:packV(2, maxx, maxy,zz, maxu, maxv)

	ctx.screen_tb:set()
end

local box = {}

local ScissorRect_index = {0,1,1,2,2,3,3,0}
local ScissorRect_state = bgfx.make_state {
					WRITE_MASK = "RGB",
					PT = "LINES",
					BLEND = "ALPHA"
				}

local ms = util.mathstack
local time = 0
local function mainloop()
	math3d.reset(ms)
	time = time + settings.lightAnimationSpeed * 0.1

	-- Setup views
	local vp
	do
		bgfx.set_view_frame_buffer(RENDER_PASS_LIGHT_ID, ctx.m_lightBuffer)
		bgfx.set_view_frame_buffer(RENDER_PASS_GEOMETRY_ID, ctx.m_gbuffer)

		bgfx.set_view_transform(RENDER_PASS_GEOMETRY_ID, ctx.view, ctx.proj)

		vp = ms(ctx.proj, ctx.view, "*P")

		bgfx.set_view_transform(RENDER_PASS_LIGHT_ID, nil, ctx.ortho)
		bgfx.set_view_transform(RENDER_PASS_COMBINE_ID, nil, ctx.ortho)

		local size = 10
		local aspectRatio = ctx.height / ctx.width
		local o = ms( { type = "mat", ortho = true, l = -size, r = size, b = size * aspectRatio, t = -size * aspectRatio, n = 0, f = 1000 }, "P")
		bgfx.set_view_transform(RENDER_PASS_DEBUG_GBUFFER_ID, nil, o)

		local o = ms( { type = "mat", ortho = true, l = 0, r = ctx.width, b = 0, t = ctx.height, n = 0, f = 1000 }, "P")
		bgfx.set_view_transform(RENDER_PASS_DEBUG_LIGHTS_ID, nil, o)
	end

	local dim = 11
	local offset = ((dim-1) * 3) * 0.5

	-- Draw into geometry pass.
	for yy = 0, dim-1 do
		for xx = 0, dim-1 do
			local srt = { type = "srt" }
			if settings.animateMesh then
				srt.r = { time * 1.023 + xx*0.21, time*0.03 + yy* 0.37, 0 }
			end
			srt.t = { -offset + xx * 3, -offset + yy * 3, 0 }
			-- Set transform for draw call.
			bgfx.set_transform(ms (srt , "P"))

			-- Set vertex and index buffer.
			bgfx.set_vertex_buffer(ctx.m_vbh)
			bgfx.set_index_buffer(ctx.m_ibh)

			-- Bind textures.
			bgfx.set_texture(0, ctx.s_texColor,ctx.m_textureColor)
			bgfx.set_texture(1, ctx.s_texNormal, ctx.m_textureNormal)

			-- Set render states.
			bgfx.set_state(ctx.state)

			-- Submit primitive for rendering to view 0.
			bgfx.submit(RENDER_PASS_GEOMETRY_ID, ctx.m_geomProgram)
		end
	end


	-- Draw lights into light buffer.
	for light = 0, settings.numLights-1 do
		local lightTime = time * settings.lightAnimationSpeed * (math.sin((light/settings.numLights) * math.pi * 0.5) * 0.5 + 0.5)
		local lightPosRadius = { -- Sphere
			math.sin( ( (lightTime + light*0.47) + math.pi * 0.5 *1.37 ) )* offset,
			math.cos( ( (lightTime + light*0.69) + math.pi * 0.5 *1.49 ) )* offset,
			math.sin( ( (lightTime + light*0.37) + math.pi * 0.5 *1.57 ) )* 2.0,
			radius = 2.0,
		}
		local aabb_min = {
			lightPosRadius[1] - lightPosRadius.radius,
			lightPosRadius[2] - lightPosRadius.radius,
			lightPosRadius[3] - lightPosRadius.radius,
		}
		local aabb_max = {
			lightPosRadius[1] + lightPosRadius.radius,
			lightPosRadius[2] + lightPosRadius.radius,
			lightPosRadius[3] + lightPosRadius.radius,
		}

		box[1] = { aabb_min[1], aabb_min[2], aabb_min[3] , 1}
		box[2] = { aabb_min[1], aabb_min[2], aabb_max[3] , 1}
		box[3] = { aabb_min[1], aabb_max[2], aabb_min[3] , 1}
		box[4] = { aabb_min[1], aabb_max[2], aabb_max[3] , 1}
		box[5] = { aabb_max[1], aabb_min[2], aabb_min[3] , 1}
		box[6] = { aabb_max[1], aabb_min[2], aabb_max[3] , 1}
		box[7] = { aabb_max[1], aabb_max[2], aabb_min[3] , 1}
		box[8] = { aabb_max[1], aabb_max[2], aabb_max[3] , 1}

		local xyz = ms (box[1], vp, "%T" )

		local maxx, maxy, maxz = xyz[1], xyz[2], xyz[3]

		local minx = maxx
		local miny = maxy

		for i=2,8 do
			xyz = ms(box[i], vp, "%T" )
			local x,y,z = xyz[1], xyz[2], xyz[3]
			minx = math.min(minx, x)
			miny = math.min(miny, y)
			maxx = math.max(maxx, x)
			maxy = math.max(maxy, y)
			maxz = math.max(maxz, z)
		end

		-- Cull light if it's fully behind camera.
		local function clamp(v, m)
			local value = (v * 0.5 + 0.5) * m
			if value < 0 then
				return 0
			end
			if value > m then
				return m
			end
			return value
		end

		if maxz >= 0 then
			local x0 = clamp(minx, ctx.width)
			local y0 = clamp(miny, ctx.height)
			local x1 = clamp(maxx, ctx.width)
			local y1 = clamp(maxy, ctx.height)

			if settings.showScissorRects then
				ctx.tb:alloc(4,8,ctx.DebugVertex)
				local abgr = 0x8000ff00
				ctx.tb:packV(0, x0,y0,0,abgr)
				ctx.tb:packV(1, x1,y0,0,abgr)
				ctx.tb:packV(2, x1,y1,0,abgr)
				ctx.tb:packV(3, x0,y1,0,abgr)

				ctx.tb:packI(ScissorRect_index)

				ctx.tb:set()
				bgfx.set_state(ScissorRect_state)

				bgfx.submit(RENDER_PASS_DEBUG_LIGHTS_ID, ctx.m_lineProgram)
			end

			local val = light & 7
			local lightRgbInnerR = ms:vector (
				(val & 0x1) ~= 0 and 1 or 0.25,
				(val & 0x2) ~= 0 and 1 or 0.25,
				(val & 0x4) ~= 0 and 1 or 0.25,
				0.8
			)

			-- Draw light.
			local lightpos = ms:vector ( lightPosRadius[1],lightPosRadius[2],lightPosRadius[3],lightPosRadius.radius )

			bgfx.set_uniform(ctx.u_lightPosRadius, lightpos)
			bgfx.set_uniform(ctx.u_lightRgbInnerR, lightRgbInnerR)
			bgfx.set_uniform(ctx.u_mtx, ms(vp, "iP"))
			local scissorHeight = y1-y0
			bgfx.set_scissor(math.floor(x0), math.floor(ctx.height - scissorHeight - y0), math.floor(x1-x0), math.floor(scissorHeight))
			bgfx.set_texture(0, ctx.s_normal, bgfx.get_texture(ctx.m_gbuffer, 1))
			bgfx.set_texture(1, ctx.s_depth, bgfx.get_texture(ctx.m_gbuffer, 2))
			bgfx.set_state(ctx.light_state)

			screenSpaceQuad( ctx.width, ctx.height, ctx.s_texelHalf, util.caps.originBottomLeft)

			bgfx.submit(RENDER_PASS_LIGHT_ID, ctx.m_lightProgram)
		end
	end

	-- Combine color and light buffers.
	bgfx.set_texture(0, ctx.s_albedo, bgfx.get_texture(ctx.m_gbuffer,     0) )
	bgfx.set_texture(1, ctx.s_light,  bgfx.get_texture(ctx.m_lightBuffer, 0) )

	bgfx.set_state(ctx.combine_state)

	screenSpaceQuad( ctx.width, ctx.height, ctx.s_texelHalf, util.caps.originBottomLeft)
	bgfx.submit(RENDER_PASS_COMBINE_ID, ctx.m_combineProgram)

	if settings.showGBuffer then
		local aspectRatio = ctx.width/ctx.height

		-- Draw m_debug m_gbuffer.
		local count = #ctx.m_gbufferTex
		for ii = 1, count do
			local mtx = ms ( { type = "srt",
				s = { aspectRatio, 1, 1 },
				t = { -7.9 - count*0.1*0.5 + (ii-1)*2.1*aspectRatio, 4.0, 0 },
			} , "P")

			bgfx.set_transform(mtx)
			bgfx.set_vertex_buffer(ctx.m_vbh)
			bgfx.set_index_buffer(ctx.m_ibh, 0, 6)
			bgfx.set_texture(0, ctx.s_texColor, ctx.m_gbufferTex[ii])
			bgfx.set_state(ctx.gbuffer_state)
			bgfx.submit(RENDER_PASS_DEBUG_GBUFFER_ID, ctx.m_debugProgram)
		end
	end

	bgfx.frame()
end

function ctx.init()
	-- Set palette color for index 0
	bgfx.set_palette_color(0, 0)

	-- Set palette color for index 1
	bgfx.set_palette_color(1, 0x303030ff)

	-- Set geometry pass view clear state.
	bgfx.set_view_clear_mrt(RENDER_PASS_GEOMETRY_ID, "CD", 1.0, 0, 1)

	-- Set light pass view clear state.
	bgfx.set_view_clear_mrt(RENDER_PASS_LIGHT_ID , "CD"	, 1.0, 0, 0	)

	-- Create vertex stream declaration.
	ctx.PosNormalTangentTexcoordVertex = bgfx.vertex_decl {
		{ "POSITION", 3, "FLOAT" },
		{ "NORMAL", 4, "UINT8", true, true },
		{ "TANGENT", 4, "UINT8", true, true },
		{ "TEXCOORD0", 2, "INT16", true, true },
	}

	ctx.PosTexCoord0Vertex = bgfx.vertex_decl {
		{ "POSITION", 3, "FLOAT" },
		{ "TEXCOORD0", 2, "FLOAT" },
	}

	ctx.DebugVertex = bgfx.vertex_decl {
		{ "POSITION", 3, "FLOAT" },
		{ "COLOR0", 4, "UINT8", true },
	}

	ctx.tb = bgfx.transient_buffer "fffd"
	ctx.screen_tb = bgfx.transient_buffer "fffff"

	local encodeNormalRgba8 = bgfxu.encodeNormalRgba8

	local s_cubeVertices = {
	"fffddss",
	-1.0,  1.0,  1.0, encodeNormalRgba8( 0.0,  0.0,  1.0), 0,      0,      0,
	 1.0,  1.0,  1.0, encodeNormalRgba8( 0.0,  0.0,  1.0), 0, 0x7fff,      0,
	-1.0, -1.0,  1.0, encodeNormalRgba8( 0.0,  0.0,  1.0), 0,      0, 0x7fff,
	 1.0, -1.0,  1.0, encodeNormalRgba8( 0.0,  0.0,  1.0), 0, 0x7fff, 0x7fff,
	-1.0,  1.0, -1.0, encodeNormalRgba8( 0.0,  0.0, -1.0), 0,      0,      0 ,
	 1.0,  1.0, -1.0, encodeNormalRgba8( 0.0,  0.0, -1.0), 0, 0x7fff,      0,
	-1.0, -1.0, -1.0, encodeNormalRgba8( 0.0,  0.0, -1.0), 0,      0, 0x7fff,
	 1.0, -1.0, -1.0, encodeNormalRgba8( 0.0,  0.0, -1.0), 0, 0x7fff, 0x7fff,
	-1.0,  1.0,  1.0, encodeNormalRgba8( 0.0,  1.0,  0.0), 0,      0,      0 ,
	 1.0,  1.0,  1.0, encodeNormalRgba8( 0.0,  1.0,  0.0), 0, 0x7fff,      0,
	-1.0,  1.0, -1.0, encodeNormalRgba8( 0.0,  1.0,  0.0), 0,      0, 0x7fff,
	 1.0,  1.0, -1.0, encodeNormalRgba8( 0.0,  1.0,  0.0), 0, 0x7fff, 0x7fff,
	-1.0, -1.0,  1.0, encodeNormalRgba8( 0.0, -1.0,  0.0), 0,      0,      0 ,
	 1.0, -1.0,  1.0, encodeNormalRgba8( 0.0, -1.0,  0.0), 0, 0x7fff,      0,
	-1.0, -1.0, -1.0, encodeNormalRgba8( 0.0, -1.0,  0.0), 0,      0, 0x7fff,
	 1.0, -1.0, -1.0, encodeNormalRgba8( 0.0, -1.0,  0.0), 0, 0x7fff, 0x7fff,
	 1.0, -1.0,  1.0, encodeNormalRgba8( 1.0,  0.0,  0.0), 0,      0,      0 ,
	 1.0,  1.0,  1.0, encodeNormalRgba8( 1.0,  0.0,  0.0), 0, 0x7fff,      0,
	 1.0, -1.0, -1.0, encodeNormalRgba8( 1.0,  0.0,  0.0), 0,      0, 0x7fff,
	 1.0,  1.0, -1.0, encodeNormalRgba8( 1.0,  0.0,  0.0), 0, 0x7fff, 0x7fff,
	-1.0, -1.0,  1.0, encodeNormalRgba8(-1.0,  0.0,  0.0), 0,      0,      0 ,
	-1.0,  1.0,  1.0, encodeNormalRgba8(-1.0,  0.0,  0.0), 0, 0x7fff,      0,
	-1.0, -1.0, -1.0, encodeNormalRgba8(-1.0,  0.0,  0.0), 0,      0, 0x7fff,
	-1.0,  1.0, -1.0, encodeNormalRgba8(-1.0,  0.0,  0.0), 0, 0x7fff, 0x7fff,
	}
	local s_cubeIndices = {
	 0,  2,  1,
	 1,  2,  3,
	 4,  5,  6,
	 5,  7,  6,

	 8, 10,  9,
	 9, 10, 11,
	12, 13, 14,
	13, 15, 14,

	16, 18, 17,
	17, 18, 19,
	20, 21, 22,
	21, 23, 22,
	}

	-- Create static vertex buffer.
	ctx.m_vbh = bgfx.create_vertex_buffer(s_cubeVertices, ctx.PosNormalTangentTexcoordVertex, "t", s_cubeIndices)
	-- Create static index buffer.
	ctx.m_ibh = bgfx.create_index_buffer(s_cubeIndices)

	-- Create texture sampler uniforms.
	local function uni_int(name)
		ctx[name] = bgfx.create_uniform(name, "s")
	end

	uni_int "s_texColor"
	uni_int "s_texNormal"
	uni_int "s_albedo"
	uni_int "s_normal"
	uni_int "s_depth"
	uni_int "s_light"

	ctx.u_mtx            = bgfx.create_uniform("u_mtx",            "m4")
	ctx.u_lightPosRadius = bgfx.create_uniform("u_lightPosRadius", "v4")
	ctx.u_lightRgbInnerR = bgfx.create_uniform("u_lightRgbInnerR", "v4")

	-- Create program from shaders.
	ctx.m_geomProgram    = util.programLoad("vs_deferred_geom",       "fs_deferred_geom")
	ctx.m_lightProgram   = util.programLoad("vs_deferred_light",      "fs_deferred_light")
	ctx.m_combineProgram = util.programLoad("vs_deferred_combine",    "fs_deferred_combine")
	ctx.m_debugProgram   = util.programLoad("vs_deferred_debug",      "fs_deferred_debug")
	ctx.m_lineProgram    = util.programLoad("vs_deferred_debug_line", "fs_deferred_debug_line")

	-- Load diffuse texture.
	ctx.m_textureColor  = util.textureLoad "textures/fieldstone-rgba.dds"

	-- Load normal texture.
	ctx.m_textureNormal = util.textureLoad "textures/fieldstone-n.dds"

	ctx.m_gbufferTex = {}
	ctx.m_gbuffer = nil
	ctx.m_lightBuffer = nil

	ctx.state = bgfx.make_state {
		WRITE_MASK = "RGBAZ",
		DEPTH_TEST = "LESS",
		MSAA = true
	}

	ctx.light_state = bgfx.make_state {
		WRITE_MASK = "RGBA",
		BLEND = "ADD",
	}

	ctx.combine_state = bgfx.make_state {
		WRITE_MASK = "RGBA",
	}

	ctx.gbuffer_state = bgfx.make_state {
		WRITE_MASK = "RGB",
	}
	ctx.s_texelHalf = util.caps.rendererType == "DIRECT3D9" and 0.5 or 0

	if util.caps.limits.maxFBAttachments < 2 then
		mainloop = function()
			bgfx.set_debug "T"
			bgfx.dbg_text_print(0, 0, 0x1f, " MRT not supported by GPU. ")
			bgfx.touch(0)
			bgfx.frame()
		end
	end
end

function ctx.resize(w,h)
	ctx.width = w
	ctx.height = h
	bgfx.reset(w,h, "v")
	bgfx.destroy(ctx.m_gbuffer)

	local samplerFlags = "rt-p+p*pucvc"
	--[[
		| BGFX_TEXTURE_RT
		| BGFX_TEXTURE_MIN_POINT
		| BGFX_TEXTURE_MAG_POINT
		| BGFX_TEXTURE_MIP_POINT
		| BGFX_TEXTURE_U_CLAMP
		| BGFX_TEXTURE_V_CLAMP
	]]
	ctx.m_gbufferTex[1] = bgfx.create_texture2d(w, h, false, 1, "BGRA8" , samplerFlags)
	ctx.m_gbufferTex[2] = bgfx.create_texture2d(w, h, false, 1, "BGRA8" , samplerFlags)
	ctx.m_gbufferTex[3] = bgfx.create_texture2d(w, h, false, 1, "D24S8"   , samplerFlags)
	ctx.m_gbuffer = bgfx.create_frame_buffer(ctx.m_gbufferTex, true)

	bgfx.destroy(ctx.m_lightBuffer)
	ctx.m_lightBuffer = bgfx.create_frame_buffer(w,h,"BGRA8", samplerFlags)

	ctx.view = ms:ref "matrix" ( ms ( { 0.0, 0.0, -15.0, }, { 0,0,0 }, "lP" ) )
	ctx.proj = ms:ref "matrix" { type = "mat", fov = 60, aspect = w/h , n = 0.1, f = 100 }
	ctx.ortho = ms:ref "matrix" { type = "mat", ortho = true,
		l = 0, r = 1, b = 1, t = 0, n = 0, f = 100 }

	bgfx.set_view_rect(RENDER_PASS_GEOMETRY_ID,      0, 0, w, h )
	bgfx.set_view_rect(RENDER_PASS_LIGHT_ID,         0, 0, w, h )
	bgfx.set_view_rect(RENDER_PASS_COMBINE_ID,       0, 0, w, h )
	bgfx.set_view_rect(RENDER_PASS_DEBUG_LIGHTS_ID,  0, 0, w, h )
	bgfx.set_view_rect(RENDER_PASS_DEBUG_GBUFFER_ID, 0, 0, w, h )

end

util.init(ctx)
dlg:showxy(iup.CENTER,iup.CENTER)
dlg.usersize = nil
util.run(mainloop)
