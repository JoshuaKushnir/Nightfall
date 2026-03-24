--!strict
--[[
    Class: Packets
    Description: Data quantization for network compression. Provides functions to pack and unpack Vectors and CFrames.
    Dependencies: None
    Usage: local Packets = require(path.to.Packets)
]]

local Packets = {}

-- Quantizes a Vector3 to 16-bit integers (lossy compression)
function Packets.QuantizeVector3(vec: Vector3, minXYZ: Vector3, maxXYZ: Vector3): (number, number, number)
	local function quantize(val: number, min: number, max: number): number
		local range = max - min
		local normalized = math.clamp((val - min) / range, 0, 1)
		return math.floor(normalized * 65535 + 0.5)
	end

	return quantize(vec.X, minXYZ.X, maxXYZ.X),
		   quantize(vec.Y, minXYZ.Y, maxXYZ.Y),
		   quantize(vec.Z, minXYZ.Z, maxXYZ.Z)
end

-- Dequantizes 16-bit integers back to a Vector3
function Packets.DequantizeVector3(qX: number, qY: number, qZ: number, minXYZ: Vector3, maxXYZ: Vector3): Vector3
	local function dequantize(val: number, min: number, max: number): number
		local range = max - min
		local normalized = val / 65535
		return min + (normalized * range)
	end

	return Vector3.new(
		dequantize(qX, minXYZ.X, maxXYZ.X),
		dequantize(qY, minXYZ.Y, maxXYZ.Y),
		dequantize(qZ, minXYZ.Z, maxXYZ.Z)
	)
end

-- Quantizes a CFrame position and compresses rotation
function Packets.QuantizeCFrame(cf: CFrame, minXYZ: Vector3, maxXYZ: Vector3): (number, number, number, Vector3)
	local qX, qY, qZ = Packets.QuantizeVector3(cf.Position, minXYZ, maxXYZ)
	local look = cf.LookVector
	local lookMin = Vector3.new(-1, -1, -1)
	local lookMax = Vector3.new(1, 1, 1)
	local lqX, lqY, lqZ = Packets.QuantizeVector3(look, lookMin, lookMax)
	return qX, qY, qZ, Vector3.new(lqX, lqY, lqZ)
end

-- Dequantizes to a CFrame (Position + Look at)
function Packets.DequantizeCFrame(qX: number, qY: number, qZ: number, qLookVec: Vector3, minXYZ: Vector3, maxXYZ: Vector3): CFrame
	local pos = Packets.DequantizeVector3(qX, qY, qZ, minXYZ, maxXYZ)

	local lookMin = Vector3.new(-1, -1, -1)
	local lookMax = Vector3.new(1, 1, 1)
	local look = Packets.DequantizeVector3(qLookVec.X, qLookVec.Y, qLookVec.Z, lookMin, lookMax)

	return CFrame.new(pos, pos + look)
end

return Packets
