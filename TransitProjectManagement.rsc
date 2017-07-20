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
  Log where stops don't have a scenario node nearby.
Place this value into Node_ID.
Run the create-from-table batch macro.
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

  // Update the values of MacroOpts
  MacroOpts.output_rts_file = output_rts_file
  MacroOpts.centroid_qry = centroid_qry
  MacroOpts.out_dir = out_dir

  RunMacro("Create Scenario Route System", MacroOpts)
  RunMacro("Update Scenario Attributes", MacroOpts)
  RunMacro("Check Scenario Route System", MacroOpts)
EndMacro

/*
Creates the scenario route system.
*/

Macro "Create Scenario Route System" (MacroOpts)

  // Argument extraction
  master_rts = MacroOpts.master_rts
  scen_hwy = MacroOpts.scen_hwy
  proj_list = MacroOpts.proj_list
  centroid_qry = MacroOpts.centroid_qry
  output_rts_file = MacroOpts.output_rts_file
  out_dir = MacroOpts.out_dir

  // Make a copy of the master_rts into the output directory to prevent
  // this macro from modifying the actual master RTS.
  opts = null
  opts.from_rts = master_rts
  opts.to_dir = out_dir
  opts.include_hwy_files = "true"
  {master_rts_copy, master_hwy_copy} = RunMacro("Copy RTS Files", opts)

  // Get project IDs from the project list
  proj_df = CreateObject("df")
  proj_df.read_csv(proj_list)
  v_pid = proj_df.get_vector("ProjID")

  // Convert the project IDs into route IDs
  opts = null
  opts.rts_file = master_rts
  opts.v_id = v_pid
  v_rid = RunMacro("Convert ProjID to RouteID", opts)

  // Open the route's stop dbd and add the scen_hwy
  master_stops_dbd = Substitute(master_rts_copy, ".rts", "S.dbd", )
  opts = null
  opts.file = master_stops_dbd
  {map, } = RunMacro("Create Map", opts)
  {slyr} = GetDBLayers(master_stops_dbd)
  {nlyr, llyr} = GetDBLayers(scen_hwy)
  AddLayer(map, nlyr, scen_hwy, nlyr)
  AddLayer(map, llyr, scen_hwy, llyr)

  // Create a selection set of route stops from the proj_list using
  // the route IDs. (The ProjID field is not in the stops dbd.)
  SetLayer(slyr)
  route_stops = "scenario routes"
  for i = 1 to v_rid.length do
    id = v_rid[i]

    id = if TypeOf(id) = "string" then "'" + id + "'" else String(id)
    qry = "Select * where Route_ID = " + id
    operation = if i = 1 then "several" else "more"
    SelectByQuery(route_stops, operation, qry)
  end

  /*
  Add stop layer fields. The tour table required to create a fresh route
  system requires the following fields:
  Route_Number
  Node_ID
  Stop_Flag
  Stop_ID
  Stop_Name

  On a freshly-created route system, only the following fields are present
  on the stop layer:
  Route_ID (can be renamed to Route_Number)
  STOP_ID (can be renamed to Stop_ID)

  Thus, the following fields must be created:
  Stop_Flag (filled with 1 because these are stop records)
  Node_ID (filled by tagging stops to nodes)
  Stop_Name (left empty)

  A final field "missing_node" is added for reporting purposes.
  */
  a_fields = {
    {"Stop_Flag", "Integer", 10,,,,,"Filled with 1s"},
    {"Stop_Name", "Character", 10,,,,,""},
    {"Node_ID", "Integer", 10,,,,,"Scenario network node id"},
    {"missing_node", "Integer", 10,,,,,
    "1: a stop in the master rts could not find a nearby node"}
  }
  RunMacro("Add Fields", slyr, a_fields, {1, , , 0})

  // Create a selection set of centroids on the node layer. These will be
  // excluded so that routes do not pass through them. Also create a
  // non-centroid set.
  SetLayer(nlyr)
  centroid_set = CreateSet("centroids")
  num_centroids = SelectByQuery(centroid_set, "several", centroid_qry)
  non_centroid_set = CreateSet("non-centroids")
  SetInvert(non_centroid_set, centroid_set)

  // Perform a spatial join to match scenario nodes to master nodes.
  opts = null
  opts.master_layer = slyr
  opts.master_set = route_stops
  opts.slave_layer = nlyr
  opts.slave_set = non_centroid_set
  jv = RunMacro("Spatial Join", opts)

  // Transfer the scenario node ID into the Node_ID field
  v = GetDataVector(jv + "|", nlyr + ".ID", )
  SetDataVector(jv + "|", slyr + ".Node_ID", v, )
  CloseView(jv)
  // The spatial join leaves a "slave_id" field. Remove it.
  RunMacro("Drop Field", slyr, {"slave_id", "slave_dist"})

  // Read in the selected records to a data frame
  stop_df = CreateObject("df")
  opts = null
  opts.view = slyr
  opts.set = route_stops
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
    {"Route_ID", "STOP_ID", "Stop Name"},
    {"Route_Number", "Stop_ID", "Stop_Name"}
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

  // Get the name of the master (copy) route layer
  {, , a_info} = GetRouteSystemInfo(master_rts_copy)
  rlyr = a_info.Name

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

  // Clean up the files created by this macro that aren't needed anymore
  RunMacro("Close All")
  DeleteTableFiles("FFB", tour_table, )
  DeleteFile(net_file)
EndMacro

/*
Updates the scenario route system attributes based on the TransitProjectList.csv
*/

Macro "Update Scenario Attributes" (MacroOpts)

  // Argument extraction
  master_rts = MacroOpts.master_rts
  scen_hwy = MacroOpts.scen_hwy
  proj_list = MacroOpts.proj_list
  centroid_qry = MacroOpts.centroid_qry
  output_rts_file = MacroOpts.output_rts_file

  // Read in the parameter file
  param = CreateObject("df")
  param.read_csv(proj_list)

  // Create a map of the scenario RTS
  opts = null
  opts.file = output_rts_file
  {map, {rlyr}} = RunMacro("Create Map", opts)
  SetLayer(rlyr)

  // Loop over column names and update attributes. ProjID is skipped.
  a_colnames = param.colnames()
  // Only do this process if columns other than ProjID exist.
  if a_colnames.length > 1 then do
    for col_name in a_colnames do
      if col_name = "ProjID" then continue

      // Create a data frame that filters out null values from this column
      temp = param.copy()
      temp.filter(col_name + " <> null")

      // Break if this column is empty
      test = temp.is_empty()
      if temp.is_empty() then continue

      {v_pid, v_value} = temp.get_vector({"ProjID", col_name})
      for i = 1 to v_pid.length do
        pid = v_pid[i]
        value = v_value[i]

        // Locate the route with this project ID. If not found, throw an error.
        opts = null
        opts.Exact = "true"
        rh = LocateRecord(rlyr + "|", "ProjID", {pid}, opts)
        if rh = null then do
          pid_string = if TypeOf(pid) = "string" then pid else String(pid)
          Throw("ProjID '" + pid_string + "' not found in route layer")
        end

        // Update the attribute
        SetRecord(rlyr, rh)
        rlyr.(col_name) = value
      end
    end
  end

  CloseMap(map)
EndMacro

/*

*/

Macro "Check Scenario Route System" (MacroOpts)

  // Argument extraction
  master_rts = MacroOpts.master_rts
  scen_hwy = MacroOpts.scen_hwy
  proj_list = MacroOpts.proj_list
  centroid_qry = MacroOpts.centroid_qry
  output_rts_file = MacroOpts.output_rts_file
  out_dir = MacroOpts.out_dir

  // Create path to the copy of the master rts and highway files
  {drive, path, filename, ext} = SplitPath(master_rts)
  master_rts_copy = out_dir + "/" + filename + ext
  opts = null
  opts.rts_file = master_rts_copy
  master_hwy_copy = RunMacro("Get RTS Highway File", opts)

  // Summarize the number of missing nodes by route. In order to have
  // all the fields in one table, you have to open the RTS file, which
  // links multiple tables together.
  opts = null
  opts.file = master_rts_copy
  {master_map, {rlyr_m, slyr_m, , , llyr_m}} = RunMacro("Create Map", opts)
  stops_df = CreateObject("df")
  opts = null
  opts.view = slyr_m
  opts.fields = {"Route_ID", "missing_node"}
  stops_df.read_view(opts)
  stops_df.mutate("missing_node", nz(stops_df.get_vector("missing_node")))
  stops_df.group_by("Route_ID")
  agg = null
  agg.missing_node = {"sum"}
  stops_df.summarize(agg)
  stops_df.rename("sum_missing_node", "missing_node")

  // Open the scenario route system in a separate map.
  opts = null
  opts.file = output_rts_file
  {scen_map, {rlyr_s, slyr_s, , , llyr_s}} = RunMacro("Create Map", opts)
  v_pid = GetDataVector(rlyr_s + "|", "ProjID", )

  // Compare route lengths between master and scenario
  data = null
  for pid in v_pid do
    // Calculate the route length in the master rts
    opts = null
    opts.rlyr = rlyr_m
    opts.llyr = llyr_m
    opts.pid = pid
    length_m = RunMacro("Get Route Length", opts)
    // Calculate the route length in the scenario rts
    opts = null
    opts.rlyr = rlyr_s
    opts.llyr = llyr_s
    opts.pid = pid
    length_s = RunMacro("Get Route Length", opts)

    // calculate difference and percent difference
    diff = length_s - length_m
    pct_diff = diff / length_m

    // store this information in a named array
    data.ProjID = data.ProjID + {pid}
    data.master_length = data.master_length + {length_m}
    data.scenario_length = data.scenario_length + {length_s}
    data.diff = data.diff + {diff}
    data.pct_diff = data.pct_diff + {pct_diff}
  end

  // Close both maps
  CloseMap(master_map)
  CloseMap(scen_map)

  // Convert the named array into a data frame
  length_df = CreateObject("df", data)

  // Convert the project IDs into route IDs
  opts = null
  opts.rts_file = master_rts_copy
  opts.v_id = length_df.get_vector("ProjID")
  v_rid = RunMacro("Convert ProjID to RouteID", opts)
  length_df.mutate("Route_ID", v_rid)

  // Create the final data frame by joining the missing stops and length DFs
  final_df = length_df.copy()
  final_df.left_join(stops_df, "Route_ID", "Route_ID")
  final_df.select({
    "ProjID", "Route_ID", "master_length", "scenario_length",
    "diff", "pct_diff", "missing_node"
  })
  final_df.rename("missing_node", "missing_nodes")
  final_df.write_csv(out_dir + "/_rts_creation_results.csv")


  // Clean up files
  RunMacro("Close All")
  DeleteRouteSystem(master_rts_copy)
  if GetFileInfo(Substitute(master_rts_copy, ".rts", "R.bin", )) <> null
    then DeleteFile(Substitute(master_rts_copy, ".rts", "R.bin", ))
  if GetFileInfo(Substitute(master_rts_copy, ".rts", "R.BX", )) <> null
    then DeleteFile(Substitute(master_rts_copy, ".rts", "R.BX", ))
  if GetFileInfo(Substitute(master_rts_copy, ".rts", "R.DCB", )) <> null
    then DeleteFile(Substitute(master_rts_copy, ".rts", "R.DCB", ))
  DeleteDatabase(master_hwy_copy)
EndMacro

/*
Helper macro used to convert project IDs (which are on the route layer) to
route IDs (which are included on the node and link tables of the route layer).

Inputs
  MacroOpts
    Named array that holds arguments (e.g. MacroOpts.master_rts)

    rts_file
      String
      Full path to the .rts file that contains both route and project IDs

    v_id
      Array or vector of project IDs (or route IDs if reverse = "true")

    reverse
      Optional String ("true"/"false")
      Defaults to false. If true, converts route IDs into project IDs

Returns
  A vector of route IDs corresponding to the input project IDs
*/

Macro "Convert ProjID to RouteID" (MacroOpts)

  // Argument extraction
  rts_file = MacroOpts.rts_file
  v_id = MacroOpts.v_id
  reverse = MacroOpts.reverse

  if reverse = null then reverse = "false"

  // Create map of RTS
  opts = null
  opts.file = rts_file
  {map, {rlyr, slyr, phlyr}} = RunMacro("Create Map", opts)

  // Convert project IDs into route IDs
  SetLayer(rlyr)
  route_set = "scenario routes"
  for i = 1 to v_id.length do
    id = v_id[i]

    id = if TypeOf(id) = "string" then "'" + id + "'" else String(id)
    qry = if reverse
      then "Select * where Route_ID = " + id
      else "Select * where ProjID = " + id
    operation = if i = 1 then "several" else "more"
    n = SelectByQuery(route_set, operation, qry)
    if n = 0 then do
      string = if reverse
        then "Route with Route_ID = " + id + " not found in route layer."
        else "Route with ProjID = " + id + " not found in route layer."
      Throw(string)
    end
  end
  v_result = if reverse
    then GetDataVector(rlyr + "|" + route_set, "ProjID", )
    else GetDataVector(rlyr + "|" + route_set, "Route_ID", )

  CloseMap(map)
  return(v_result)
EndMacro

/*
Helper function for "Check Scenario Route System".
Determines the length of the links that make up a route.
If this ends being used by multiple macros in different scripts, move it
to the ModelUtilities.rsc file.

MacroOpts
  Named array that holds other arguments (e.g. MacroOpts.rlyr)

  rlyr
    String
    Name of route layer

  llyr
    String
    Name of the link layer

  pid
    Integer
    Route ID

Returns
  Length of route
*/

Macro "Get Route Length" (MacroOpts)

  // Argument extraction
  rlyr = MacroOpts.rlyr
  llyr = MacroOpts.llyr
  pid = MacroOpts.pid

  // Determine the current layer before doing work to set it back after the
  // macro finishes.
  cur_layer = GetLayer()

  // Get route name based on the route id
  SetLayer(rlyr)
  opts = null
  opts.Exact = "true"
  rh = LocateRecord(rlyr + "|", "ProjID", {pid}, opts)
  if rh = null then Throw("Route_ID not found")
  SetRecord(rlyr, rh)
  route_name = rlyr.Route_Name

  // Get IDs of links that the route runs on
  a_links = GetRouteLinks(rlyr, route_name)
  for link in a_links do
    a_lid = a_lid + {link[1]}
  end

  // Determine length of those links
  SetLayer(llyr)
  n = SelectByIDs("route_links", "several", a_lid, )
  if n = 0 then Throw("Route links not found in layer '" + llyr + "'")
  v_length = GetDataVector(llyr + "|route_links", "Length", )
  length = VectorStatistic(v_length, "Sum", )

  // Set the layer back to the original if there was one.
  if cur_layer <> null then SetLayer(cur_layer)

  return(length)
EndMacro
