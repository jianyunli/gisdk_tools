/*
Creates a simple .net file using just the length attribute. Many processes
require a network

Inputs
  MacroOpts
    Named array holding all arguments. (e.g. MacroOpts.hwy_dbd)

    llyr
      String - provide either llyr or hwy_dbd (not both)
      Name of line layer to create network from. If provided, the macro assumes
      the layer is already in the workspace. Either 'llyr' or 'hwy_dbd' must
      be provided.

    hwy_dbd
      String - provide either llyr or hwy_dbd (not both)
      Full path to the highway DBD file to create a network. If provided, the
      macro assumes that it is not already open in the workspace.Either 'llyr'
      or 'hwy_dbd' must be provided.

    centroid_qry
      Optional String
      Query defining centroid set. If null, a centroid set will not be created.
      e.g. "FCLASS = 99"

Returns
  net_file
    String
    Full path to the network file created by the network. Will be in the
    same directory as the hwy_dbd.
*/

Macro "Create Simple Highway Net" (MacroOpts)

  RunMacro("TCB Init")

  // Argument extraction
  llyr = MacroOpts.llyr
  llyr_provided = if (llyr <> null) then "true" else "false"
  hwy_dbd = MacroOpts.hwy_dbd
  hwy_dbd_provided = if (hwy_dbd <> null) then "true" else "false"
  centroid_qry = MacroOpts.centroid_qry

  // Argument checking
  if !llyr_provided and !hwy_dbd_provided = null then Throw(
    "Either 'llyr' or 'hwy_dbd' must be provided."
  )
  if llyr_provided and hwy_dbd_provided then Throw(
    "Provide only 'llyr' or 'hwy_dbd'. Not both."
  )

  // If llyr is provided, get the hwy_dbd
  // Get info about hwy_dbd
  if llyr_provided then do
    map = GetMap()
    SetLayer(llyr)
    if map = null then Throw("Simple Network: 'llyr' must be in current map")
    a_layers = GetMapLayers(map, "Line")
    in_map = if (ArrayPosition(a_layers, {llyr}, ) = 0) then "false" else "true"
    if !in_map then Throw("Simple Network: 'llyr' must be in the current map")

    hwy_dbd = GetLayerDB(llyr)
    {nlyr, } = GetDBLayers(hwy_dbd)
  // if hwy_dbd is provided, open it in a map
  end else do
    {nlyr, llyr} = GetDBLayers(hwy_dbd)
    map = RunMacro("G30 new map", hwy_dbd)
  end
  a_path = SplitPath(hwy_dbd)
  out_dir = RunMacro("Normalize Path", a_path[1] + a_path[2])

  // Create a simple network of the scenario highway layer
  SetLayer(llyr)
  set_name = null
  net_file = out_dir + "/simple.net"
  label = "Simple Network"
  link_fields = {{"Length", {llyr + ".Length", llyr + ".Length", , , "False"}}}
  node_fields = null
  opts = null
  opts.[Time Units] = "Minutes"
  opts.[Length Units] = "Miles"
  opts.[Link ID] = llyr + ".ID"
  opts.[Node ID] = nlyr + ".ID"
  opts.[Turn Penalties] = "Yes"
  nh = CreateNetwork(set_name, net_file, label, link_fields, node_fields, opts)

  // Add centroids to the network to prevent routes from passing through
  // Network Settings
  if centroid_qry <> null then do

    centroid_qry = RunMacro("Normalize Query", centroid_qry)

    Opts = null
    Opts.Input.Database = hwy_dbd
    Opts.Input.Network = net_file
    Opts.Input.[Centroids Set] = {
      hwy_dbd + "|" + nlyr, nlyr,
      "centroids", centroid_qry
    }
    ok = RunMacro("TCB Run Operation", "Highway Network Setting", Opts, &Ret)
    if !ok then Throw(
      "Simple Network: Setting centroids failed"
    )
  end

  // Workspace clean up.
  // If this macro create the map, then close it.
  if hwy_dbd_provided then CloseMap(map)

  return(net_file)
EndMacro

/*
Creates a fully-specified highway network file (.net) using paramter files.
More complex version of "Create Simple Highway Network".

MacroOpts
  Named array of arguments

  hwy_dbd
    String
    Path to the highway DBD file to create a .net file from

  settings_tbl
    String
    Path to a csv with network settings (except field definitions)

  fields_tbl
    String
    Path to a csv with the link and node fields to include in .net
*/

Macro "Create Highway Network" (MacroOpts)

  // Argument extraction
  hwy_dbd = MacroOpts.hwy_dbd
  settings_tbl = MacroOpts.settings_tbl
  fields_tbl = MacroOpts.fields_tbl




EndMacro
