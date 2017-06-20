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
  RunMacro("Transit Project Management", opts)
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

    proj_list
      String
      Full path to the CSV file containing the list of routes to include

Outputs
  Creates a new RTS file in the same folder as scen_hwy
*/

Macro "Transit Project Management" (MacroOpts)

  // Argument extraction and checking
  master_rts = MacroOpts.master_rts
  scen_hwy = MacroOpts.scen_hwy
  proj_list = MacroOpts.proj_list
  if master_rts = null then Throw("'master_rts' not provided")
  if scen_hwy = null then Throw("'scen_hwy' not provided")
  if proj_list = null then Throw("'proj_list' not provided")

  // Convert project IDs into route IDs
  proj_df = CreateObject("df")
  proj_df.read_csv(proj_list)
  v_pid = proj_df.get_vector("ProjID")
  {rlyr, slyr, phlyr} = RunMacro("TCB Add RS Layers", master_rts, "ALL",)
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
  RunMacro("Close All")

  // Open the route's stop dbd and add the scen_hwy
  stops_dbd = Substitute(master_rts, ".rts", "S.dbd", )
  map = RunMacro("G30 new map", stops_dbd)
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

  // Add a field called Node_ID
  a_fields = {
    {"Node_ID", "Integer", 10,,,,,"Scenario network node id"}
  }
  RunMacro("Add Fields", slyr, a_fields, 0)

  // Select the nearest scenario node features to the RTS stop features,
  // putting the ids into the Node_ID field.
  units = GetMapUnits("Plural")
  threshold = if (units = "Miles") then 100 / 5280
    else if (units = "Feet") then 100
  if threshold = null then Throw("Map units must be feet or miles")
  SetLayer(nlyr)
  nearest_node_set = "nearest nodes"
  n = SelectNearestFeatures(
    neares_node_set, "several", slyr + "|" + route_set, threshold,
  )
  v_scen_node_ids = GetDataVector(nlyr + "|" + nearest_node_set, "ID", )
  SetDataVector(slyr + "|" + route_set, "Node_ID", v_scen_node_ids, )
Throw()
  // Read in the selected records to a data frame
  stop_df = CreateObject("df")
  opts = null
  opts.view = slyr
  opts.set = "proj_routes"
  stop_df.read_view(opts)


EndMacro
