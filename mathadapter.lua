local bgfx = require "bgfx"
local adapter = require "math3d.adapter"

return function (ms)
	bgfx.set_transform = adapter.matrix(ms, bgfx.set_transform, 1, 1)
	bgfx.set_view_transform = adapter.matrix(ms, bgfx.set_view_transform, 2, 2)
	bgfx.set_uniform = adapter.variant(ms, bgfx.set_uniform_matrix, bgfx.set_uniform_vector, 2)
end
