/*
Library of tools to create scenario RTS files by extracting from a master
layer and moving to a scenario network.

General approach and notes:
Every route system (RTS) has a stops dbd file. It ends with "S.dbd".
Opening it gives every piece of information needed to use TransCADs
"Create Route from Table" batch macro.

Select from this layer based on project ID.
Export this selection to a new bin file.
Format the new table to look like what is required by the creation macro
  hover over it and hit F1 for help, which shows the table needed
  Includes creating a new field called Node_ID
Loop over each row to get the nearest node from the new layer.
Place this value into Node_ID.
Run the create-from-table batch macro.
  Use the skimming options to capture distance.
  Compare distance to previous route to check for large deviations.
*/

Macro "test"

  RunMacro("Close All")

  model_dir = "Y:\\projects/OahuMPO/Repo"
  scen_dir = model_dir + "/scenarios/test"
  opts = null
  opts.master_rts = model_dir + "/generic/inputs/master_network/Oahu Route System 102907.rts"
  opts.scen_hwy = scen_dir + "/inputs/network/Scenario Line Layer.dbd"
  opts.proj_list = scen_dir + "/TransitProjectList.csv"
  opts.centroid_qry = "[Zone Centroid] = 'Y'"
  opts.output_rts_file = "Scenario Route System.rts"
  RunMacro("Transit Project Management", opts)

  ShowMessage("Done")
EndMacro

/*
Inputs
  MacroOpts
    Named array containing all function arguments

    master_rts
      String
      Full path to the master RTS file
      The RTS file must have a field called ProjID that contains values matching
      the proj_list CSV file.

    scen_hwy
      String
      Full path to the scenario highway dbd that should have the routes loaded

    centroid_qry
      String
      Query that defines centroids in the node layer. Centroids will be prevented
      from having stops tagged to them. Routes will also be prevented from
      traveleing through them.

    proj_list
      String
      Full path to the CSV file containing the list of routes to include

    output_rts_file
      Optional String
      The file name desired for the output route system.
      Defaults to "ScenarioRoutes.rts".
      Do not include the full path. The route system will always be created
      in the same folder as the scenario highway file.

Outputs
  Creates a new RTS file in the same folder as scen_hwy
*/

Macro "Transit Project Management" (MacroOpts)

  RunMacro("Create Scenario Route System", MacroOpts)
  RunMacro("Update Scenario Attributes", MacroOpts)
  RunMacro("Check Scenario Route System", MacroOpts)
EndMacro

/*
Creates the scenario route system.
*/

Macro "Create Scenario Route System" (Macro Opts)
  // To prevent potential problems with view names, open files, etc.
  // close everything before starting.
  RunMacro("Close All")

  // Argument extraction
  master_rts = MacroOpts.master_rts
  scen_hwy = MacroOpts.scen_hwy
  proj_list = MacroOpts.proj_list
  centroid_qry = MacroOpts.centroid_qry
  output_rts_file = MacroOpts.output_rts_file

  // Argument checking
  if master_rts = null then Throw("'master_rts' not provided")
  if scen_hwy = null then Throw("'scen_hwy' not provided")
  if proj_list = null then Throw("'proj_list' not provided")
  if centroid_qry = null then Throw("'centroid_qry' not provided")
  centroid_qry = RunMacro("Normalize Query", centroid_qry)
  if output_rts_file = null then output_rts_file = "ScenarioRoutes.rts"

  // Set the output directory to be the same as the scenario highway
  a_path = SplitPath(scen_hwy)
  out_dir = a_path[1] + a_path[2]
  out_dir = RunMacro("Normalize Path", out_dir)
  output_rts_file = out_dir + "/" + output_rts_file

  // Make a copy of the master_rts into the output directory to prevent
  // this macro from modifying the actual master RTS.
  opts = null
  opts.from_rts = master_rts
  opts.to_dir = out_dir
  opts.include_hwy_files = "true"
  {master_rts_copy, master_hwy_copy} = RunMacro("Copy RTS Files", opts)

  // Create map of RTS
  opts = null
  opts.file = master_rts
  {map, {rlyr, slyr, phlyr}} = RunMacro("Create Map", opts)

  // Convert project IDs into route IDs
  proj_df = CreateObject("df")
  proj_df.read_csv(proj_list)
  v_pid = proj_df.get_vector("ProjID")
  SetLayer(rlyr)
  route_set = "scenario routes"
  for i = 1 to v_pid.length do
    id = v_pid[i]

    id = if TypeOf(id) = "string" then "'" + id + "'" else String(id)
    qry = "Select * where ProjID = " + id
    operation = if i = 1 then "several" else "more"
    n = SelectByQuery(route_set, operation, qry)
    if n = 0 then Throw(
      "Route with ProjID = " + id + " not found in master layer."
    )
  end
  v_rid = GetDataVector(rlyr + "|" + route_set, "Route_ID", )
  CloseMap(map)

  // Open the route's stop dbd and add the scen_hwy
  stops_dbd = Substitute(master_rts_copy, ".rts", "S.dbd", )
  opts = null
  opts.file = stops_dbd
  {map, } = RunMacro("Create Map", opts)
  {slyr} = GetDBLayers(stops_dbd)
  {nlyr, llyr} = GetDBLayers(scen_hwy)
  AddLayer(map, nlyr, scen_hwy, nlyr)
  AddLayer(map, llyr, scen_hwy, llyr)

  // Create a selection set of routes in the proj_list using
  // the route IDs. (The ProjID field is not in the stops dbd.)
  SetLayer(slyr)
  route_set = "scenario routes"
  for i = 1 to v_rid.length do
    id = v_rid[i]

    id = if TypeOf(id) = "string" then "'" + id + "'" else String(id)
    qry = "Select * where Route_ID = " + id
    operation = if i = 1 then "several" else "more"
    SelectByQuery(route_set, operation, qry)
  end

  // Add stop layer fields called Node_ID and missing_node
  a_fields = {
    {"Node_ID", "Integer", 10,,,,,"Scenario network node id"},
    {"missing_node", "Integer", 10,,,,,
    "1: a stop in the master rts could not find a nearby node"}
  }
  RunMacro("Add Fields", slyr, a_fields, {0, 0})

  // Setup the search threshold for SelectNearestFeatures
  units = GetMapUnits("Plural")
  threshold = if (units = "Miles") then 100 / 5280
    else if (units = "Feet") then 100
  if threshold = null then Throw("Map units must be feet or miles")

  // Create a selection set of centroids on the node layer
  SetLayer(nlyr)
  num_centroids = SelectByQuery("centroids", "several", centroid_qry)

  // Loop over each stop in the table and find the nearest scenario node ID
  rh = GetFirstRecord(slyr + "|" + route_set, )
  while rh <> null do

    // Create a stop set to hold the current record
    SetRecord(slyr, rh)
    SetLayer(slyr)
    current_stop_set = "current stop"
    CreateSet(current_stop_set)
    SelectRecord(current_stop_set)

    // Locate the nearest node in the node layer to the current stop. Exclude
    // centroids from being nearest features.
    SetLayer(nlyr)
    nearest_node_set = "nearest nodes"
    opts = null
    opts.[Source Not] = "centroids"
    n = SelectNearestFeatures(
      nearest_node_set, "several", slyr + "|" + current_stop_set,
      threshold, opts
    )
    if n = 0 then slyr.missing_node = 1
    else do
      n_id = GetSetIDs(nlyr + "|" + nearest_node_set)
      n_id = n_id[1]
      slyr.Node_ID = n_id
    end

    SetLayer(slyr)
    UnselectRecord(current_stop_set)
    rh = GetNextRecord(slyr + "|" + route_set, , )
  end

  // Read in the selected records to a data frame
  stop_df = CreateObject("df")
  opts = null
  opts.view = slyr
  opts.set = route_set
  stop_df.read_view(opts)

  // Create a table with the proper format to be read by TC's
  // create-route-from-table method. In TC6 help, this is called
  // "Creating a Route System from a Tour Table", and is in the drop down
  // menu Route Systems -> Utilities -> Create from table...
  // Fields:
  // Route_Number
  // Node_ID
  // Stop_Flag
  // Stop_ID
  // Stop_Name
  create_df = stop_df.copy()
  create_df.rename(
    {"Route_ID", "STOP_FLAG", "STOP_ID", "Stop Name"},
    {"Route_Number", "Stop_Flag", "Stop_ID", "Stop_Name"}
  )
  create_df.filter("missing_node <> 1")
  create_df.select(
    {"Route_Number", "Node_ID", "Stop_Flag", "Stop_ID", "Stop_Name"}
  )
  tour_table = out_dir + "/create_rts_from_table.bin"
  create_df.write_bin(tour_table)

  // Create a simple network
  opts = null
  opts.llyr = llyr
  opts.centroid_qry = "[Zone Centroid] = 'Y'"
  net_file = RunMacro("Create Simple Highway Net", opts)

  // Call TransCAD macro for importing a route system from a stop table.
  Opts = null
  Opts.Input.Network = net_file
  Opts.Input.[Link Set] = {scen_hwy + "|" + llyr, llyr}
  Opts.Input.[Tour Table] = {tour_table}
  Opts.Global.[Cost Field] = 1
  Opts.Global.[Route ID Field] = 1
  Opts.Global.[Node ID Field] = 2
  Opts.Global.[Include Stop] = 1
  Opts.Global.[RS Layers].RouteLayer = rlyr
  Opts.Global.[RS Layers].StopLayer = slyr
  Opts.Global.[Stop Flag Field] = 3
  Opts.Global.[User ID Field] = 2
  Opts.Output.[Output Routes] = output_rts_file
  ret_value = RunMacro("TCB Run Operation", "Create RS From Table", Opts, &Ret)
  if !ret_value then Throw("Create RS From Table failed")
  // The tcb method leaves a layer open. Use close all to close it and the map.
  RunMacro("Close All")

  // The new route system is created without attributes. Join them back.
  master_df = CreateObject("df")
  master_df.read_bin(
    Substitute(master_rts_copy, ".rts", "R.bin", )
  )
  scen_df = CreateObject("df")
  scen_df.read_bin(
    Substitute(output_rts_file, ".rts", "R.bin", )
  )
  scen_df.remove({"Route_Name", "Time", "Distance"})
  scen_df.left_join(master_df, "Route_Number", "Route_ID")
  scen_df.update_bin(
    Substitute(output_rts_file, ".rts", "R.bin", )
  )

  // Reload the route system, which takes care of a few issues created by the
  // create-from-stops and join steps.
  opts = null
  opts.file = output_rts_file
  {map, a_layers} = RunMacro("Create Map", opts)
  ReloadRouteSystem(output_rts_file)

  // Clean up the files created by this macro
  RunMacro("Close All")
  DeleteRouteSystem(master_rts_copy)
  if GetFileInfo(Substitute(master_rts_copy, ".rts", "R.bin", )) <> null
    then DeleteFile(Substitute(master_rts_copy, ".rts", "R.bin", ))
  if GetFileInfo(Substitute(master_rts_copy, ".rts", "R.BX", )) <> null
    then DeleteFile(Substitute(master_rts_copy, ".rts", "R.BX", ))
  if GetFileInfo(Substitute(master_rts_copy, ".rts", "R.DCB", )) <> null
    then DeleteFile(Substitute(master_rts_copy, ".rts", "R.DCB", ))
  DeleteDatabase(master_hwy_copy)
  DeleteTableFiles("FFB", tour_table, )
  DeleteFile(net_file)
EndMacro

/*
Updates the scenario route system attrbiutes based on the TransitProjectList.csv
*/

Macro "Update Scenario Attributes" (MacroOpts)

EndMacro
