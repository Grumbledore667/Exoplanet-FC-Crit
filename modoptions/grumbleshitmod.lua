-- Persistent Data
local multiRefObjects = {

} -- multiRefObjects
local obj1 = {
	["name"] = "Grumbledores CritPartial HitMod";
	["options"] = {
		[1] = {
			["defaultvalue"] = true;
			["element"] = "checkbox";
			["label"] = "Activate/Deactivate Mod";
		};
		[2] = {
			["defaultvalue"] = true;
			["element"] = "checkbox";
			["label"] = "Use Partial hit";
		};
		[3] = {
			["defaultvalue"] = true;
			["element"] = "checkbox";
			["label"] = "Use Critical hit";
		};
		[4] = {
			["defaultvalue"] = "[colour='FFFF6347']Normal";
			["descriptions"] = {
				[1] = "[colour='FF00FF00']Easy";
				[2] = "[colour='FFFF6347']Normal";
				[3] = "[colour='FFFF0000']DIE";
			};
			["element"] = "radio";
			["groupid"] = "667";
			["label"] = "Difficulty";
		};
	};
}
return obj1
