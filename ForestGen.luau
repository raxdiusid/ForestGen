-- Discord: raxdiusid | Roblox: raxdiusid

--!strict
--!optimize 2

-- Built-in services
local ReplicatedStorage      = game:GetService("ReplicatedStorage")
local RunService 	         = game:GetService("RunService")
local Debris                 = game:GetService("Debris")
local Players                = game:GetService("Players")

-- ForestGen compulsory internal components
local ForestGenMod = ReplicatedStorage:WaitForChild("ForestGen")
local FGenEvents   = ForestGenMod:WaitForChild("Events")
local FGTypes 	   = require(ForestGenMod.FGTypes)
local FEnums	   = require(ForestGenMod.Enums)
local FGUtil	   = require(ForestGenMod.FGUtil)

-- ForestGen compulsory remote events
local TreeReplication: RemoteEvent = FGenEvents:WaitForChild("TreeReplication")

local ForestGen   = {Enums=FEnums}
ForestGen.__index = ForestGen

export type ForestGen = typeof(setmetatable(
	{} :: {
		Connection         : RBXScriptConnection?,
		Soil               : BasePart,
		SamplingRate       : number,
		FGenInstancesFolder: Folder,
		MaxTree            : number,
		TreesStats         : {[string]: {[string]: any}},
		RawTreeAmount      : number,
		FlatTreesType      : {
			{
				Name     : string,
				Generator: (ForestGen, string, Vector3) -> Model,
				Property : {[string]: any}
			}
		},
		ProbabilitySpace   : FGTypes.ProbabilitySpace,
		_ProbLowerBound    : number,
		_IsRestarting      : boolean
	},
	ForestGen
	))

function ForestGen.new(Soil: BasePart, SamplingRate: number, MaxTree: number): ForestGen
	--[[
		Generates a ForestGen context.
		
		Args:
			Soil: A Part or BasePart which is used by ForestGen to grow trees on.
			SamplingRate: A numerical rate of how many trees will be added each minute.
			MaxTree: A numerical number that determines how many trees can be grown on `Soil`
		Returns:
			ForestGen
	]]
	local self               = setmetatable({}, ForestGen)
	self.Soil                = Soil
	self.MaxTree             = MaxTree
	self.SamplingRate        = SamplingRate
	self.Connection          = nil :: RBXScriptConnection?
	self.RawTreeAmount       = 0
	self.FGenInstancesFolder = workspace:FindFirstChild("FGenFolder") :: Folder
	self._ProbLowerBound     = 1
	if not self.FGenInstancesFolder then
		self.FGenInstancesFolder        = Instance.new("Folder")
		self.FGenInstancesFolder.Name   = "FGenInstancesFolder"
		self.FGenInstancesFolder.Parent = workspace
	end
	self.TreesStats       = {}
	self.ProbabilitySpace = {}
	self.FlatTreesType    = {}
	self._IsRestarting    = false
	return self
end

function ForestGen.Run(self: ForestGen)
	--[[
		A core loop that is utilized by ForestGen to continuously generate trees
		and control their behaviours.
		
		Args:
			ForestGen: ForestGen ctx
		
		Returns: none
	]]
	assert(not self.Connection, "[ForestGen] A connection has already existed.")
	
	local Old = tick()
	local SamplingInterval = 60/self.SamplingRate
	
	local Generators = RunService.Heartbeat:Connect(function(deltaTime: number)
		if self:IsMaximumTreeReached() then
			if not self._IsRestarting then
				self._IsRestarting = true
			end
			return
		end
		
		if self._IsRestarting then
			Old = tick() + SamplingInterval
			self._IsRestarting = false
		end
		
		local Now     = tick()
		local Elapsed = Now-Old
		
		if Elapsed < SamplingInterval then
			return
		end
		
		local RandomPositionOnSoil = self.Soil.Position+Vector3.new(
			math.random(-self.Soil.Size.X/2, self.Soil.Size.X/2),
			3,
			math.random(-self.Soil.Size.Z/2, self.Soil.Size.Z/2)
		)
		
		local SelectedTree, TreeModel: Model = self:RandomTreeSelection(RandomPositionOnSoil)
		
		TreeModel.Parent = self.FGenInstancesFolder:FindFirstChild(SelectedTree.Name)
		TreeModel:SetAttribute("Health", 3)
		TreeModel:GetAttributeChangedSignal("Health"):Connect(function()
			local HealthAttr = TreeModel:GetAttribute("Health")
			
			if HealthAttr > 0 then
				return
			end
			
			for _, TreePart: Part in pairs(TreeModel:GetChildren() :: {Part}) do
				TreePart.Anchored = false
				if TreePart.Name == "Bark" then
					local ProximityPrompt = Instance.new("ProximityPrompt")
					ProximityPrompt.Parent = TreePart
					ProximityPrompt.MaxActivationDistance = 8
					ProximityPrompt.HoldDuration = 0.1
					ProximityPrompt.ActionText = "Collect"
					ProximityPrompt.Triggered:Connect(function(Player: Player)
						TreePart:Destroy()
						TreeReplication:FireServer(SelectedTree.Name, TreePart.Size, TreePart.Color)
					end)
					Debris:AddItem(TreePart, 500)
					continue
				end
				Debris:AddItem(TreePart, 10)
			end
			
			local CustomOnDestroyed: () -> () = SelectedTree.Property.OnDestroyed
			
			if CustomOnDestroyed then
				CustomOnDestroyed()
			end
			
			self.RawTreeAmount -= 1
		end)
		
		self.TreesStats[SelectedTree.Name].Occurence += 1
		TreeModel.Name = string.format("%s%d", SelectedTree.Name, self.TreesStats[SelectedTree.Name].Occurence)
		self.RawTreeAmount += 1
		Old = tick()
	end)
	
	self.Connection = Generators
end

function ForestGen.BasicTree(self: ForestGen, Name: string, Position: Vector3, Color: BrickColor?): Model
	--[[
		Built-in tree variant. Generate a simple, brown-painted tree.
		
		Args:
			ForestGen: ForestGen ctx.
			Name (string): The name of the tree that is used as a unique identifier.
			Position (Vector3): Three-dimensional data that is used to position the tree.
			Color (BrickColor?): The color of the tree.
		
		Returns:
			Model
	]]
	local NumberOfBranch    = math.random(1, 5)
	local TreeModel: Model  = Instance.new("Model")
	
	local TreeCenter        = Instance.new("Part")
	TreeCenter.Size         = Vector3.new(2, 2, 2)
	TreeCenter.Position     = Position
	TreeCenter.Parent       = TreeModel
	TreeCenter.Anchored     = true
	TreeCenter.CanCollide   = false
	TreeCenter.Transparency = 1
	
	TreeModel.PrimaryPart   = TreeCenter
	
	local TreeBranch: any = {self.CreateAttachableTreeBody(self.Soil, TreeModel, Position, Color)}
	for i = 1, NumberOfBranch do
		local Branch = TreeBranch[i]:Attach(self.CreateAttachableTreeBody(nil, TreeModel, nil, Color))
		table.insert(TreeBranch, Branch)
	end
	local LastBranch      = TreeBranch[#TreeBranch]
	
	local TopLeave        = FGUtil:CreateStudPart()
	TopLeave.Parent       = TreeModel
	TopLeave.BrickColor   = BrickColor.new("Sea green")
	TopLeave.Size         = Vector3.new(7, 0.9, 7)
	TopLeave.Anchored     = true
	TopLeave.CFrame       = LastBranch.PrimaryPart.CFrame * CFrame.new(0, LastBranch.PrimaryPart.Size.Y/2, 0)
	
	return TreeModel
end

function ForestGen.BirchTree(self: ForestGen, Name: string, Position: Vector3): Model
	--[[
		Built-in tree variant. Generate a simple, wheat-painted tree.
		
		Args:
			ForestGen: ForestGen ctx.
			Name (string): The name of the tree that is used as a unique identifier.
			Position (Vector3): Three-dimensional data that is used to position the tree.
		
		Returns:
			Model
	]]
	return self:BasicTree(Name, Position, BrickColor.new("Wheat"))
end

function ForestGen.CreateAttachableTreeBody(Soil: BasePart?, Parent: Model, Position: Vector3?, Color: BrickColor?)
	--[[
		This function is meant for internal use and is used for built-in trees variant
		such as `ForestGen.BasicTree (oak)` and `ForestGen.Birch`.
		
		Creates an attachable body of the tree that can be smoothly attached to another part of the
		tree.
		
		Args:
			Soil: BasePart?: The place trees will be positioned on.
			Parent (Parent): Holder which tree parts are parented to.
			Position (Vector3): Three-dimensional data that is used to position the tree.
			Color (BrickColor): The color of the tree.
		
		Returns:
			TreeBody
	]]
	assert(Parent.PrimaryPart, "[ForestGen] Primary part doesn't exist.")
	
	local TreeBody 	  = {}
	
	local Bark: Part  = FGUtil:CreateStudPart()
	Bark.Size         = Vector3.new(1.5, 8, 1)
	Bark.BrickColor   = Color or BrickColor.new("Brown")
	Bark.Name         = "Bark"
	Bark.Anchored     = true
	Bark.Parent       = Parent
	
	if Position then
		Bark.Position = Position
	end
	TreeBody.PrimaryPart = Bark
	
	if Soil then
		Bark.Position = Vector3.new(Bark.Position.X, Soil.Position.Y+Bark.Size.Y/2, Bark.Position.Z)
	end
	
	function TreeBody.Attach(self, AnotherTreeBody)
		local AnotherTreeBodyPrimary: Part = AnotherTreeBody.PrimaryPart
		local DeviationAngle = math.rad(math.random(-20, 20))
		AnotherTreeBodyPrimary.CFrame = (Bark.CFrame:ToWorldSpace(CFrame.new(-Bark.Size.X/2, Bark.Size.Y/2, 0)*CFrame.fromEulerAngles(0, 0, DeviationAngle)))
			:ToWorldSpace(CFrame.new(Bark.Size.X/2, Bark.Size.Y/2, 0))
    
		if DeviationAngle > 0 then
			AnotherTreeBodyPrimary.CFrame *= CFrame.new(0, -Bark.Size.X*math.sin(DeviationAngle), 0)
		end
    
		return AnotherTreeBody
	end
	
	return TreeBody
end

function ForestGen.AddTreeType(self: ForestGen, TreeName: string, TreeGenerator: (ForestGen, string, Vector3) -> Model, Property: {[string]: any})
	--[[
		Adding a variant of tree into the table `ForestGen.FlatTreesType`. Tree model
		is generated via user-given function `TreeGenerator` that must yield a `Model`
		and tree model is customized using parameter `Property`.
		
		Args:
			ForestGen: ForestGen ctx.
			TreeName (string): The name of the tree that is used as a unique identifier.
			TreeGenerator ((ForestGen, string, Vector3) -> Model): Tree generator that yields a Model.
		
		Returns: none
	]]
	table.insert(self.FlatTreesType, {
		Name=TreeName,
		Generator=TreeGenerator,
		Property=Property
	})
	
	local TreeTypeFolder = Instance.new("Folder")
	TreeTypeFolder.Name = TreeName
	TreeTypeFolder.Parent = self.FGenInstancesFolder
	
	self.TreesStats[TreeName] = {
		Occurence=0
	}
	
	table.insert(self.ProbabilitySpace, {
		lb=self._ProbLowerBound,
		ub=self._ProbLowerBound+Property.Probability
	})
	
	self._ProbLowerBound += Property.Probability+1
end

function ForestGen.RandomTreeSelection(self: ForestGen, Position: Vector3): any
	--[[
		Randomly picking a tree in the table `ForestGen.FlatTreesType`
		adjusted with user-given probability. It works by categorizing trees by
		'Upper Bound (UB)' and 'Lower Bound (LB)' and the fact that `math.random` gives
		equal distribution of numbers, the picked tree is a tree which `RandomPick` sits between
		UB and LB of the tree.
		
		Args:
			ForestGen: ForestGen ctx.
			Position (Vector3): Three-dimensional data that is used to position the tree.
		
		Returns:
			none
			|
			({
				Name: string,
				Generator: (ForestGen, string, Vector3) -> Model,
				Property: {
					Health: number,
					Probability: number,
					OnDestroyed: (any) -> any
				}
			}, Model)
	]]
	local RandomPick: number = math.random(1, self._ProbLowerBound-1)
	for TreeIndex, TreeProbability in self.ProbabilitySpace do
		if RandomPick < TreeProbability.lb or RandomPick > TreeProbability.ub then
			continue
		end
		local SelectedTree: any = self.FlatTreesType[TreeIndex]
		local SelectedGenerator = SelectedTree.Generator
		return SelectedTree, SelectedGenerator(self, SelectedTree.Name, Position)
	end
	warn("[ForestGen] Probability Space is misconfigured.")
	return
end

function ForestGen.IsMaximumTreeReached(self: ForestGen): boolean
	--[[
		Checking if the number of trees reached the predetermined
		threshold.
		
		Args:
			ForestGen: ForestGen ctx.
			
		Returns:
			bool: Maximum of trees reached.
	]]
	return self.RawTreeAmount >= self.MaxTree
end

function ForestGen.Clean(self: ForestGen)
	--[[
		Clean unused RBXConnection to free some used memory.
		
		Args:
			ForestGen: ForestGen ctx.
			
		Returns: none
	]]
	assert(self.Connection, "[ForestGen] No connection is running.")
	self.Connection:Disconnect()
end

return ForestGen
