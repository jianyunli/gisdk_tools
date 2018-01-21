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
    Path to a csv with the link and node fields to include in .net. AB/BA field
    specs can include expression variables (e.g. {period}). These will be
    normalized using the 'expr_vars' array.
    For example:

    layer	net_field_name	ab_field_spec	  ba_field_spec
    ----------------------------------------------------
    link	Capacity	      AB{period}CapE  BA{period}CapE

  expr_vars
    Optional named array
    If the fields_tbl includes variables (e.g. {period}) in the AB/BA field
    specs, include them here so that they will evaluate correctly.
    For example:

    expr_vars.period = "AM"

    Thus, the AB field spec in fields_tbl would evaluate to "ABAMCapE".

  out_file
    String
    Path to the output .net file that will be created

  label
    Optional string
    Network label. Default is "network"

*/

Macro "Create Highway Network" (MacroOpts)

  // Argument extraction
  hwy_dbd = MacroOpts.hwy_dbd
  settings_tbl = MacroOpts.settings_tbl
  fields_tbl = MacroOpts.fields_tbl
  expr_vars = MacroOpts.expr_vars
  out_file = MacroOpts.out_file
  label = MacroOpts.label

  if label = null then label = "network"

  // Open the parameter files
  settings = RunMacro("Read Parameter File", settings_tbl)
  fields = CreateObject("df")
  fields.read_csv(fields_tbl)
  link_fields = fields.copy()
  link_fields.filter("layer = 'link'")
  node_fields = fields.copy()
  node_fields.filter("layer = 'node'")

  // Open the link and node layers
  {nlyr, llyr} = GetDBLayers(hwy_dbd)
  llyr = AddLayerToWorkspace(llyr, hwy_dbd, llyr)
  nlyr = AddLayerToWorkspace(nlyr, hwy_dbd, nlyr)
  SetLayer(llyr)

  // Set u-turn and through movement angles.
  // U-turn: 10 degrees; Through: 30 degrees
  // These are the default TCv6 values, but this step ensures
  // model consistency even if a specific user has changed these values.
  // This function is undocumented.
  SetTurnMovementTolerances(
    R2I(settings.uturn_degrees),
    R2I(settings.through_degrees)
  )

  // Create a link set if query is provided
  if settings.link_query <> null then do
    SetLayer(llyr)
    set_name = CreateSet("link set")
    n = SelectByQuery(set_name, "several", settings.link_query)
  end

  // Create array of link fields to include
  for r = 1 to link_fields.nrow() do
    field_name = link_fields.tbl.net_field_name[r]
    ab_name = RunMacro(
      "Normalize Expression", link_fields.tbl.ab_field_name[r], expr_vars
    )
    ab_spec = llyr + "." + ab_name
    ba_name = RunMacro(
      "Normalize Expression", link_fields.tbl.ba_field_name[r], expr_vars
    )
    ba_spec = llyr + "." + ba_name

    a_link_fields = a_link_fields + {
      {field_name, {ab_spec, ba_spec, , , "False"}}
    }
  end

  // Create an array of node fields to include
  for r = 1 to node_fields.nrow() do
    field_name = node_fields.tbl.net_field_name[r]
    ab_name = RunMacro(
      "Normalize Expression", node_fields.tbl.ab_field_name[r], expr_vars
    )
    ab_spec = nlyr + "." + ab_name
    ba_name = RunMacro(
      "Normalize Expression", node_fields.tbl.ba_field_name[r], expr_vars
    )
    ba_spec = nlyr + "." + ba_name

    a_node_fields = a_node_fields + {
      {field_name, {ab_spec, ba_spec, , , "False"}}
    }
  end

  opts = null
  opts.[Link ID] = llyr + ".ID"
  opts.[Node ID] = nlyr + ".ID"
  opts.[Turn Penalties] = if settings.use_turn_penalties
    then "Yes"
    else "No"
  nh = CreateNetwork(set_name, out_file, label, a_link_fields, a_node_fields, opts)

  // Network Settings
  SetNetworkInformationItem(nh, "Length Unit", {settings.distance_units})
  SetNetworkInformationItem(nh, "Time Unit", {settings.time_units})
  opts = null
  if settings.link_type_settings <> null then do
    opts.[Use Link Types] = "true"
    opts.[Link Type Settings] = settings.link_type_settings
  end
  opts.[Use Turn Penalties] = settings.use_turn_penalties
  opts.[Turn Settings] = {
    settings.left_tp,
    settings.right_tp,
    settings.straight_tp,
    settings.uturn_tp,
    settings.spec_pen_file,
    settings.def_pen_file
  }
  if settings.centroid_query <> null then do
    opts.[Use Centroids] = "true"
    SetLayer(nlyr)
    centroid_set = CreateSet("centroids")
    centroid_query = RunMacro("Normalize Query", settings.centroid_query)
    n = SelectByQuery(centroid_set, "Several", centroid_query)
    if n = 0
      then Throw("No centroids found using '" + settings.centroid_query + "'")
    opts.[Centroids Set] = centroid_set
  end
  if settings.drive_link_query <> null then do
    SetLayer(llyr)
    dl_set = CreateSet("drive link set")
    n = SelectByQuery(dl_set, "several", settings.drive_link_query)
    if n = 0 then Throw(
      "No drive-to-PNR links found using query '" +
      settings.drive_link_query + "'"
    )
    opts.[Drive Link Set] = dl_set
  end
  if settings.park_and_ride_query <> null then do
    SetLayer(nlyr)
    pnr_set = CreateSet("park and ride")
    n = SelectByQuery(pnr_set, "several", settings.park_and_ride_query)
    if n = 0 then Throw(
      "No PNR nodes found using query '" +
      settings.park_and_ride_query + "'"
    )
    opts.[Park and Drive Query] = pnr_set
  end
  ChangeNetworkSettings(nh, opts)
EndMacro
