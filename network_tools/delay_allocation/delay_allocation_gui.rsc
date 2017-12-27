// Project Benefit Calculation DBox

dBox "Benefits" center,center,170,35 toolbox NoKeyboard Title:"Benefit Calculation"
  init do
    shared Args

    if Args.General.debug = 1 then do
        ShowItem("Debug")
    end

    // Default the no-build dbd to the general dbd
    if Args.Benefits.noBuildHwy = null then Args.Benefits.noBuildHwy = Args.General.hwyDBD
    Args.Benefits.noBuildHwyArray = {"Choose Highway DBD",Args.Benefits.noBuildHwy}
    Args.Benefits.PosVars.nbHwy = 2
    Args.Benefits.allBuildHwyArray = {"Choose Highway DBD",Args.Benefits.allBuildHwy}
    if Args.Benefits.allBuildHwy <> null then Args.Benefits.PosVars.abHwy = 2

    // Update the Link Field List
    {Args.Benefits.nlayer,Args.Benefits.llayer} = GetDBLayers(Args.Benefits.noBuildHwy)
    a_info = GetDBInfo(Args.Benefits.noBuildHwy)
    Args.Benefits.hwyScope = a_info[1]
    tempLink = AddLayerToWorkspace(Args.Benefits.llayer,Args.Benefits.noBuildHwy,Args.Benefits.llayer,)
    fieldList = GetFields(tempLink,"All")
    Args.General.linkFieldList = fieldList[1] // updating the general list so that all dBoxs benefit
    DropLayerFromWorkspace(tempLink)

    // Initialize the delay units list
    Args.Benefits.unitList = {"mins","hours"}

    // Setup the array that will control which dbox items are updated
    // when the dBox is opened or settings are loaded.
    Args.GUI.Benefits.ItemList = {
      {"popNBHwy",,Args.Benefits.noBuildHwy,Args.Benefits.noBuildHwyArray,"nbHwy"},
      {"popABHwy",,Args.Benefits.allBuildHwy,Args.Benefits.allBuildHwyArray,"abHwy"},
      {"popProjID",,Args.Benefits.projID,Args.General.linkFieldList,"projID"},
      {"popFlow",,Args.Benefits.abFlow,Args.General.linkFieldList,"abFlow"},
      {"popCap",,Args.Benefits.abCap,Args.General.linkFieldList,"abCap"},
      {"popDelay",,Args.Benefits.abDelay,Args.General.linkFieldList,"abDelay"},
      {"popDelayUnits",,Args.Benefits.abDelayUnits,Args.Benefits.unitList,"abDelayUnits"}
    }

    if Args.Benefits.length <> null then RunMacro("Set Benefits Dbox Items")

  enditem


	// No-Build Highway DBD drop down menu
	Popdown Menu "popNBHwy" 12, 2, 100, 7 prompt: "No-Build Highway" list: Args.Benefits.noBuildHwyArray variable:Args.Benefits.PosVars.nbHwy do
    on escape goto quit
    if Args.Benefits.PosVars.nbHwy = 1 then do
      Args.Benefits.noBuildHwy = ChooseFile({{"Geographic File (*.dbd)", "*.dbd"}}, "Choose Highway DBD",{{"Initial Directory",Args.General.initialDir}})
      // path = SplitPath(Args.Benefits.noBuildHwy)
      // Args.Benefits.noBuildHwyArray = {"Choose Highway DBD",path[3] + path[4]}
      Args.Benefits.noBuildHwyArray = {"Choose Highway DBD",Args.Benefits.noBuildHwy}
      Args.Benefits.PosVars.nbHwy = 2

      {Args.Benefits.nlayer,Args.Benefits.llayer} = GetDBLayers(Args.Benefits.noBuildHwy)
      a_info = GetDBInfo(Args.Benefits.noBuildHwy)
      Args.Benefits.hwyScope = a_info[1]

      tempLink = AddLayerToWorkspace(Args.Benefits.llayer,Args.Benefits.noBuildHwy,Args.Benefits.llayer,)
      fieldList = GetFields(tempLink,"All")
      Args.General.linkFieldList = fieldList[1]
      DropLayerFromWorkspace(tempLink)
    end
    quit:
    on escape default
	enditem

    // All-Build Highway DBD drop down menu
	Popdown Menu "popABHwy" same, after, 100, 7 prompt: "All-Build Highway" list: Args.Benefits.allBuildHwyArray variable:Args.Benefits.PosVars.abHwy do
    on escape goto quit
    if Args.Benefits.PosVars.abHwy = 1 then do
      Args.Benefits.allBuildHwy = ChooseFile({{"Geographic File (*.dbd)", "*.dbd"}}, "Choose Highway DBD",{{"Initial Directory",Args.General.initialDir}})
      // path = SplitPath(Args.Benefits.allBuildHwy)
      // Args.Benefits.allBuildHwyArray = {"Choose Highway DBD",path[3] + path[4]}
      Args.Benefits.allBuildHwyArray = {"Choose Highway DBD",Args.Benefits.allBuildHwy}
      Args.Benefits.PosVars.abHwy = 2
    end
    quit:
    on escape default
	enditem

  // Choose the Project ID Field
  Popdown Menu "popProjID" same, after, 20, 8 prompt: "ProjectID" list: Args.General.linkFieldList variable: Args.Benefits.PosVars.projID do
    Args.Benefits.projID = Args.General.linkFieldList[Args.Benefits.PosVars.projID]

    // In order to use the project ID to make selections later, determine if the field
    // is made up of strings or numbers
    temp = AddLayerToWorkspace(Args.Benefits.llayer,Args.Benefits.noBuildHwy,Args.Benefits.llayer)
    Args.Benefits.projIDType = GetFieldTableType(Args.Benefits.llayer + "." + Args.Benefits.projID)
    DropLayerFromWorkspace(temp)
	enditem

  // Choose AB Flow Field
  Text same,after Variable:"(BA fields are found automatically)"
  Popdown Menu "popFlow" same, after, 20, 8 prompt: "AB Daily Flow" list: Args.General.linkFieldList variable: Args.Benefits.PosVars.abFlow do
    Args.Benefits.abFlow = Args.General.linkFieldList[Args.Benefits.PosVars.abFlow]
    temp = RunMacro("getBAField",Args.Benefits.abFlow, Args.General.linkFieldList)
    Args.Benefits.baFlow = temp[1]
	enditem

  // Choose AB Cap Field
  Popdown Menu "popCap" same, after, 20, 8 prompt: "AB Daily Capacity" list: Args.General.linkFieldList variable: Args.Benefits.PosVars.abCap do
    Args.Benefits.abCap = Args.General.linkFieldList[Args.Benefits.PosVars.abCap]
    temp = RunMacro("getBAField",Args.Benefits.abCap, Args.General.linkFieldList)
    Args.Benefits.baCap = temp[1]
	enditem

  // Choose FF Speed
  Popdown Menu "popFFSpeed" same, after, 20, 8 prompt: "AB FF Speed" list: Args.General.linkFieldList variable: Args.Benefits.PosVars.abffSpeed do
    Args.Benefits.abffSpeed = Args.General.linkFieldList[Args.Benefits.PosVars.abffSpeed]
    temp = RunMacro("getBAField",Args.Benefits.abffSpeed, Args.General.linkFieldList)
    Args.Benefits.baffSpeed = temp[1]
	enditem

  // Choose AB Delay Field
  Popdown Menu "popDelay" same, after, 20, 8 prompt: "AB Daily Delay" list: Args.General.linkFieldList variable: Args.Benefits.PosVars.abDelay do
    Args.Benefits.abDelay = Args.General.linkFieldList[Args.Benefits.PosVars.abDelay]
    temp = RunMacro("getBAField",Args.Benefits.abDelay, Args.General.linkFieldList)
    Args.Benefits.baDelay = temp[1]
	enditem

  // Delay units
  Popdown Menu "popDelayUnits" after, same, 10, 8 list: Args.Benefits.unitList variable: Args.Benefits.PosVars.abDelayUnits do
    Args.Benefits.abDelayUnits = Args.Benefits.unitList[Args.Benefits.PosVars.abDelayUnits]
	enditem

  // Buffer size
  Edit Text "ben_buffer" 55, 5.75, 5,1 Prompt:"Buffer Radius (mi)" Variable: Args.Benefits.buffer



  // Actual calculation
  button 20, 16, 23 Prompt:"Calculate Project Benefits" do

  enditem




  // Debug Button

  button "Debug" 5, 16, 12 Hidden do
    ShowMessage(1)
  enditem

  // Save Settings Button
  button "Save Settings" same, after, 12 do
    RunMacro("Save Settings")
  enditem

  // Load Settings Button
  button "Load Settings" same, after, 12 do
    RunMacro("Load Settings")
    RunMacro("Set Benefits Dbox Items")
  enditem

	// Quit Button
	button "Quit" 55, 16, 12 do
    Return(0)
	enditem
EndDbox
