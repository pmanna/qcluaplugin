-- Copyright (c) 2009 Paolo Manna
-- Insert here the patch inputs and their default values:
-- the plugin will create them and guess the right type to expose
-- Boolean, Numbers and Strings are mapped directly
-- Structure inputs are mapped to tables, if they've to be used inside Lua
-- If not modifiable, can be mapped to userdata assigning var to structureType()
-- To define Color input, mapped to userdata, assign var to colorType()
inputs={
	a=0,
	b="test",
	c=false,
	d=colorType()
};

-- Insert here the patch outputs: they'll be created of type consistent with the values
-- you set, but actual output values will not change until the plugin is executed
-- (typically, when an input is changed)
outputs={
	out=""
};

-- Insert here the code: the main() function will be called every time
-- Quartz Composer activates the patch
function main()
	outputs.out	= inputs.b;
end
