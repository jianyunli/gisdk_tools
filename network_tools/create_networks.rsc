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
  // Normalize any expressions/variables found in the fields table
  if expr_vars <> null then do
    fields.mutate(
      "ab_field_name",
      RunMacro("Normalize Expression", fields.tbl.ab_field_name, expr_vars)
    )
    fields.mutate(
      "ba_field_name",
      RunMacro("Normalize Expression", fields.tbl.ba_field_name, expr_vars)
    )
  end
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
  // The default is:
  // U-turn: 10 degrees; Through: 30 degrees
  // This function is undocumented.
  if settings.through_degrees = null then settings.through_degrees = 30
  if settings.uturn_degrees = null then settings.uturn_degrees = 10
  SetTurnMovementTolerances(
    R2I(settings.uturn_degrees),
    R2I(settings.through_degrees)
  )

  // The following batch macro is documented in TC GISDK help. Type in
  // "Networks" into the help index and then select "Batch Mode".
  opts = null
  opts.Input.[Link Set] = {hwy_dbd + "|" + llyr, llyr}
  if settings.link_query <> null then do
    opts.Input.[Link Set] = opts.Input.[Link Set] + {
      "link_set",
      RunMacro("Normalize Query", settings.link_query)
    }
  end
  opts.Global.[Network Label] = label
  opts.Global.[Network Options].[Turn Penalties] = "Yes"
  opts.Global.[Network Options].[Keep Duplicate Links] = "FALSE"
  opts.Global.[Network Options].[Ignore Link Direction] = "FALSE"
  opts.Global.[Network Options].[Time Units] = settings.time_units
  // Create array of link fields to include
  for r = 1 to link_fields.nrow() do
    field_name = link_fields.tbl.net_field_name[r]
    ab_spec = llyr + "." + link_fields.tbl.ab_field_name[r]
    ba_spec = llyr + "." + link_fields.tbl.ba_field_name[r]
    opts.Global.[Link Options].(field_name) = {ab_spec, ba_spec, , , "False"}
  end
  // Create an array of node fields to include
  for r = 1 to node_fields.nrow() do
    field_name = node_fields.tbl.net_field_name[r]
    ab_spec = nlyr + "." + node_fields.tbl.ab_field_name
    ba_spec = nlyr + "." + node_fields.tbl.ba_field_name[r]
    opts.Global.[Node Options].(field_name) = {ab_spec, ba_spec, , , "False"}
  end
  opts.Global.[Length Units] = settings.distance_units
  opts.Output.[Network File] = out_file
  ok = RunMacro("TCB Run Operation", "Build Highway Network", opts, &Ret)
  if !ok then Throw("Highway network creation failed")

  // Add llyr and nlyr back (the batch macro closes them)
  llyr = AddLayerToWorkspace(llyr, hwy_dbd, llyr)
  nlyr = AddLayerToWorkspace(nlyr, hwy_dbd, nlyr)

  // The code below calls the TransCAD batch macro to apply network settings.
  // This macro is documented in the help. In the GISDK help index, type
  // "settings" and then choose "Highway Networks".

  opts = null
  opts.Input.Database = hwy_dbd
  opts.Input.Network = out_file
  opts.Input.[Def Turn Pen Table] = settings.def_pen_file
  opts.Input.[Spec Turn Pen Table] = settings.spec_pen_file
  if settings.centroid_query <> null then do
    SetLayer(nlyr)
    centroid_set = CreateSet("centroid_set")
    centroid_query = RunMacro("Normalize Query", settings.centroid_query)
    n = SelectByQuery(centroid_set, "several", centroid_query)
    if n = 0
      then Throw("No centroids found using '" + settings.centroid_query + "'")
    opts.Input.[Centroids Set] = {hwy_dbd + "|" + nlyr, nlyr, centroid_set, centroid_query}
  end
  if settings.od_toll_query <> null then do
    SetLayer(llyr)
    od_toll_set = CreateSet("od_toll_set")
    od_toll_query = RunMacro("Normalize Query", settings.od_toll_query)
    n = SelectByQuery(od_toll_set, "several", od_toll_query)
    if n = 0
      then Throw("No OD toll links found using '" + settings.od_toll_query + "'")
    opts.Input.[OD Toll Set] = od_toll_set
  end
  if settings.toll_query <> null then do
    SetLayer(llyr)
    toll_set = CreateSet("toll_set")
    toll_query = RunMacro("Normalize Query", settings.toll_query)
    n = SelectByQuery(toll_set, "several", toll_query)
    if n = 0
      then Throw("No fixed toll links found using '" + settings.toll_query + "'")
    opts.Input.[Toll Set] = toll_set
  end
  Opts.Global.[Link to Link Penalty Method] = "Table"
  opts.Global.[Global Turn Penalties] = {
    settings.left_tp,
    settings.right_tp,
    settings.straight_tp,
    settings.uturn_tp
  }
  if (settings.xfer_pen_field <> null and settings.xfer_line_type_field = null) or
    (settings.xfer_pen_field = null and settings.xfer_line_type_field <> null)
    then Throw(
      "Both 'xfer_pen_field' and 'xfer_line_type_field' must be provided\n" +
      "if either is."
    )
  if settings.xfer_pen_field <> null then do
    if settings.def_pen_file <> null or settings.spec_pen_file <> null
      then Throw(
        "A transfer penalty field on the link layer cannot be used with a turn penalty table. Remove one or the other."
      )
    opts.Field.[Line ID] = settings.xfer_line_type_field
    opts.Field.[Xfer Pen] = settings.xfer_pen_field
  end
  ok = RunMacro("TCB Run Operation", "Network Settings", opts, &Ret)
  if !ok then Throw("Highway network settings failed")

  RunMacro("Close All")
EndMacro
