/*
Delay Allocation Method

Throughout this code, variables with suffix "_b" will refer to the build layer
and "_nb" to no-build. "_o" will refer to the output.
*/

Macro "Delay Allocation" (Args)
  shared MacroOpts
  MacroOpts = Args // handles GISDK memory error

  RunMacro("Close All")
  //CreateProgressBar("Delay Allocation", "True")

  // Steps
  RunMacro("da create variables")
  RunMacro("da initial calculations")
  RunMacro("da classify benefits")
  RunMacro("da allocate secondary benefits")

  RunMacro("Close All")
  //DestroyProgressBar()
EndMacro

/*
Adds variables to MacroOpts that will be used my multiple macros
*/

Macro "da create variables"
  shared MacroOpts

  // output highway file
  MacroOpts.hwy_o = MacroOpts.output_dir + "/delay_allocation.dbd"
EndMacro

/*

*/

Macro "da initial calculations"
  shared MacroOpts

  // Extract arguments
  hwy_b = MacroOpts.hwy_b
  hwy_nb = MacroOpts.hwy_nb
  param_file = MacroOpts.param_file
  output_dir = MacroOpts.output_dir
  hwy_o = MacroOpts.hwy_o

  // Argument check
  if hwy_b = null then Throw("Delay Allocation: 'hwy_b' is missing")
  if hwy_nb = null then Throw("Delay Allocation: 'hwy_nb' is missing")
  if param_file = null then Throw("Delay Allocation: 'param_file' is missing")
  if output_dir = null then Throw("Delay Allocation: 'output_dir' is missing")

  // Read the parameter table
  params = RunMacro("Read Parameter File", param_file)

  // Create the output directory
  if GetDirectoryInfo(output_dir, "All") = null then CreateDirectory(output_dir)

  // Create a copy of the all-build dbd without centroid connectors
  // (Exporting is much faster than copying and deleting links)
  {nlyr_b, llyr_b} = GetDBLayers(hwy_b)
  llyr_b = AddLayerToWorkspace(llyr_b, hwy_b, llyr_b)
  SetLayer(llyr_b)
  params.cc_class = if TypeOf(params.cc_class) = "string"
    then "'" + params.cc_class + "'"
    else String(params.cc_class)
  qry = "Select * where " + params.fclass_field + " <> " + params.cc_class
  SelectByQuery("to_export", "Several", qry)
  opts = null
  {, opts.[Field Spec]} = GetFields(llyr_b, "All")
  opts.[Layer Name] = "da_link"
  opts.[Node Name] = "da_node"
  opts.Label = "Delay Allocation Output Layer"
  ExportGeography(llyr_b + "|to_export", hwy_o, opts)
  DropLayerFromWorkspace(llyr_b)

  // Open the output highway layer
  {nlyr_o, llyr_o} = GetDBLayers(hwy_o)
  llyr_o = AddLayerToWorkspace(llyr_o, hwy_o, llyr_o)

  // Collect data from the build layer
  // (convert any nulls to zeros)
  data_b = CreateObject("df")
  a_fieldnames = {
    "ID", "Length", "Dir", params.projid_field,
    params.ab_vol, params.ba_vol,
    params.ab_cap, params.ba_cap,
    params.ab_delay, params.ba_delay
  }
  opts = null
  opts.view = llyr_o
  opts.fields = a_fieldnames
  opts.null_to_zero = "True"
  data_b.read_view(opts)

  // Collect data from the nobuild layer (joined to build)
  {nlyr_nb, llyr_nb} = GetDBLayers(hwy_nb)
  llyr_nb = AddLayerToWorkspace(llyr_nb, hwy_nb, llyr_nb)
  vw_join = JoinViews("output+nobuild", llyr_o + ".ID", llyr_nb+".ID", )
  SetView(vw_join)
  data_nb = CreateObject("df")
  opts = null
  opts.view = vw_join
  opts.fields = llyr_nb + "." + A2V(a_fieldnames)
  opts.null_to_zero = "True"
  data_nb.read_view(opts)
  data_nb.rename(opts.fields, a_fieldnames)

  // Clean up workspace
  CloseView(vw_join)
  DropLayerFromWorkspace(llyr_nb)

  // Calculate absolute and pct volume changes from no build to build
  v_abdiff = data_b.get_vector(params.ab_vol) - data_nb.get_vector(params.ab_vol)
  v_badiff = data_b.get_vector(params.ba_vol) - data_nb.get_vector(params.ba_vol)
  v_totdiff = v_abdiff + v_badiff
  v_abpctdiff = min(999, v_abdiff / (data_nb.get_vector(params.ab_vol) + .0001) * 100)
  v_bapctdiff = min(999, v_badiff / (data_nb.get_vector(params.ba_vol) + .0001) * 100)
  data_b.mutate("ab_vol_diff", v_abdiff)
  data_b.mutate("ba_vol_diff", v_badiff)
  data_b.mutate("tot_vol_diff", v_totdiff)
  data_b.mutate("ab_vol_pct_diff", v_abpctdiff)
  data_b.mutate("ba_vol_pct_diff", v_bapctdiff)

  // Calculate absolute and pct capacity changes from no build to build
  v_abdiff = data_b.get_vector(params.ab_cap) - data_nb.get_vector(params.ab_cap)
  v_badiff = data_b.get_vector(params.ba_cap) - data_nb.get_vector(params.ba_cap)
  v_totdiff = v_abdiff + v_badiff
  v_abpctdiff = min(999, v_abdiff / (data_nb.get_vector(params.ab_cap) + .0001) * 100)
  v_bapctdiff = min(999, v_badiff / (data_nb.get_vector(params.ba_cap) + .0001) * 100)
  data_b.mutate("ab_cap_diff", v_abdiff)
  data_b.mutate("ba_cap_diff", v_badiff)
  data_b.mutate("tot_cap_diff", v_totdiff)
  data_b.mutate("ab_cap_pct_diff", v_abpctdiff)
  data_b.mutate("ba_cap_pct_diff", v_bapctdiff)

  // Calculate delay change
  v_abdelaydiff = data_b.get_vector(params.ab_delay) - data_nb.get_vector(params.ab_delay)
  v_badelaydiff = data_b.get_vector(params.ba_delay) - data_nb.get_vector(params.ba_delay)
  v_totdelaydiff = v_abdelaydiff + v_badelaydiff
  data_b.mutate("ab_delay_diff", v_abdelaydiff)
  data_b.mutate("ba_delay_diff", v_badelaydiff)
  data_b.mutate("tot_delay_diff", v_totdelaydiff)

  // Determine unique list of project IDs
  Opts = null
  Opts.Unique = "True"
  Opts.Ascending = "False"
  v_uniqueProjID = SortVector(data_b.get_vector(params.projid_field),Opts)

  // Determine which projects change capacity
  df = data_b.copy()
  df.filter(params.projid_field + " <> null")
  df.group_by(params.projid_field)
  agg = null
  agg.tot_cap_diff = {"sum"}
  df.summarize(agg)
  df.filter("sum_tot_cap_diff <> 0")
  v_projid = df.get_vector(params.projid_field)

  // Store results in shared variable
  MacroOpts.data_b = data_b
  MacroOpts.data_nb = data_nb
  MacroOpts.params = params
  MacroOpts.v_projid = v_projid
EndMacro

/*
Parcel the benefits out into primary and secondary types
Primary: caused by improvement to the link
Secondary: caused by improvements to other, nearby links

For each link, the first step is to calculate the percentage of primary and secondary benefit

Start with rules:

New Links
                                    | Decrease Delay  |Increase Delay
    Increase Capacity (New Road)	  |                 |
        Increase Volume	            | n/a             |Primary
        Decrease Volume	            | n/a             |n/a
                                    |                 |
                                    |                 |
Existing Links				              |                 |
                                    | Decrease Delay  |Increase Delay
    Increase Capacity (Widening)   	|                 |
        Increase Volume	            | Primary         |Secondary
        Decrease Volume	            | Both (D.D.)     |n/a	                D.D. = decreased delay
    Decrease Capacity (Road Diet)	  |                 |
        Increase Volume	            | n/a             |Both (I.D.)          I.D. = increased delay
        Decrease Volume	            | Secondary       |Primary

For the cells above labelled "Both", a ratio of primary and secondary benefits
must be determined.

The change in capacity is used to approximate the proportion of primary benefit.
    i.e. capacity increases are the result of the project
The change in volume is used to approximate the proportion of secondary benefit.
    i.e. volume decreases are the result of improvement in other projects

Thus, the following ratio of ratios:

abs(%change in Cap) / ( abs(%change in Cap) + abs(%change in Vol) )

Absolute value is needed because, while capacity and volume are moving in
opposite directions, you want to know their relative magnitude.

This metric will determine how much of the change in delay on the project is due
to the project and how much is the secondary benefit from other projects.

Example 1: if a link's capacity increases by 20% and it's volume decreases by
10%: 2/3 of the delay reduction is due to the project.  That is primary benefit.
1/3 is due to improvements from other projects drawing volume away.  Secondary
benefit.

Example 2: if a link's capacity decreases by 30% and it's volume increases by
10%: 3/4 of the delay increase is due to the project. 1/4 is due to changes in
other links.
*/

Macro "da classify benefits"
  shared MacroOpts

  // Extract arguments to shorten names
  data_b = MacroOpts.data_b
  data_nb = MacroOpts.data_nb
  params = MacroOpts.params
  output_dir = MacroOpts.output_dir
  hwy_o = MacroOpts.hwy_o

  tot_cap_diff = data_b.get_vector("tot_cap_diff")
  tot_vol_diff = data_b.get_vector("tot_vol_diff")
  tot_delay_diff = data_b.get_vector("tot_delay_diff")

  // Classify delay change on each link
  v_category = Vector(data_b.nrow(),"String",)
  // Classify links with decreased delay
  v_category = if (tot_delay_diff < 0) then
    // If capacity increases
    (if tot_cap_diff >= 0 then
        // If volume increases or decreases
        (if tot_vol_diff >= 0 then "Primary" else "Both")
      // If capacity decreases
      else(if tot_cap_diff < 0 then
        // If volume increases or decreases
        (if tot_vol_diff >= 0 then "n/a" else "Secondary")
      )
    )
    // Classify links with increased delay
    else if (tot_delay_diff >= 0) then
      // If capacity increases
      (if tot_cap_diff >= 0 then
        // If volume increases or decreases
        (if tot_vol_diff >= 0 then "Secondary" else "n/a")
      // If capacity decreases
      else(if tot_cap_diff < 0 then
        // If volume increases or decreases
        (if tot_vol_diff >= 0 then "Both" else "Primary")
        )
      )
    else null

    // Overwrite the previous classification where two simple
    // rules are satisfied:
    // all delay changes on new facilities are primary
    nb_cap = data_nb.get_vector(params.ab_cap) + data_nb.get_vector(params.ba_cap)
    v_category = if (nb_cap = 0) then "Primary" else v_category
    // if capacity doesn't change, all delay changes are secondary
    v_category = if tot_cap_diff = 0 then "Secondary" else v_category
    data_b.mutate("category", v_category)

    // Calculate the ratio between capacity change and volume change. This is
    // used to distribute changes in delay between links that have both primary
    // and secondary benefits.
    v_ab_cap_pct_diff = data_b.get_vector("ab_cap_pct_diff")
    v_ab_vol_pct_diff = data_b.get_vector("ab_vol_pct_diff")
    v_ba_cap_pct_diff = data_b.get_vector("ba_cap_pct_diff")
    v_ba_vol_pct_diff = data_b.get_vector("ba_vol_pct_diff")
    v_abcapratio = nz(abs(v_ab_cap_pct_diff) / (abs(v_ab_cap_pct_diff) + abs(v_ab_vol_pct_diff)))
    v_bacapratio = nz(abs(v_ba_cap_pct_diff) / (abs(v_ba_cap_pct_diff) + abs(v_ba_vol_pct_diff)))
    v_abvolratio = nz(abs(v_ab_vol_pct_diff) / (abs(v_ab_cap_pct_diff) + abs(v_ab_vol_pct_diff)))
    v_bavolratio = nz(abs(v_ba_vol_pct_diff) / (abs(v_ba_cap_pct_diff) + abs(v_ba_vol_pct_diff)))
    data_b.mutate("ab_cap_ratio", v_abcapratio)
    data_b.mutate("ba_cap_ratio", v_bacapratio)
    data_b.mutate("ab_vol_ratio", v_abvolratio)
    data_b.mutate("ba_vol_ratio", v_bavolratio)

    // Calculate primary benefits based on this grouping
    // Multiply the benefit vectors by -1 to change a decrease in delay
    // into a positive benefit metric.
    v_ab_delay_diff = data_b.get_vector("ab_delay_diff")
    v_ba_delay_diff = data_b.get_vector("ba_delay_diff")
    v_ab_prim_ben = if v_category = "Primary"
      then v_ab_delay_diff * -1
      else if v_category = "Both"
        then v_ab_delay_diff * -1 * v_abcapratio
        else v_ab_prim_ben
    v_ba_prim_ben = if v_category = "Primary"
      then v_ba_delay_diff * -1
      else if v_category = "Both"
        then v_ba_delay_diff * -1 * v_bacapratio
        else v_ba_prim_ben
    // Calculate secondary benefits
    v_ab_sec_ben  = if v_category = "Secondary"
      then v_ab_delay_diff * -1
      else if v_category = "Both"
        then v_ab_delay_diff * -1 * v_abvolratio
        else v_ab_sec_ben
    v_ba_sec_ben  = if v_category = "Secondary"
      then v_ba_delay_diff * -1
      else if v_category = "Both"
        then v_ba_delay_diff * -1 * v_bavolratio
        else v_ba_sec_ben

    // For some reason, the above equations can lead to "negative zero"
    // results that sort as smaller than, for example, -80
    // Doesn't make sense - Have to set them to 0
    v_ab_prim_ben = if (v_ab_prim_ben < .0001 and v_ab_prim_ben > -.0001) then 0
      else v_ab_prim_ben
    v_ba_prim_ben = if (v_ba_prim_ben < .0001 and v_ba_prim_ben > -.0001) then 0
      else v_ba_prim_ben
    v_ab_sec_ben = if (v_ab_sec_ben < .0001 and v_ab_sec_ben > -.0001) then 0
      else v_ab_sec_ben
    v_ba_sec_ben = if (v_ba_sec_ben < .0001 and v_ba_sec_ben > -.0001) then 0
      else v_ba_sec_ben

    data_b.mutate("ab_prim_ben", nz(v_ab_prim_ben))
    data_b.mutate("ba_prim_ben", nz(v_ba_prim_ben))
    data_b.mutate("ab_sec_ben", nz(v_ab_sec_ben))
    data_b.mutate("ba_sec_ben", nz(v_ba_sec_ben))
    MacroOpts.data_b = data_b

    // Update the output highway layer
    update_df = data_b.copy()
    opts = null
    opts.start = "ab_vol_diff"
    opts.stop = "ba_sec_ben"
    columns = update_df.colnames(opts)
    update_df.select(columns)
    {nlyr, llyr} = GetDBLayers(hwy_o)
    llyr = AddLayerToWorkspace(llyr, hwy_o, llyr)
    update_df.update_view(llyr)

    RunMacro ("Close All")
EndMacro

/*

*/

Macro "da allocate secondary benefits"
  shared MacroOpts

  // Extract arguments to shorten names
  params = MacroOpts.params
  hwy_o = MacroOpts.hwy_o
  data_b = MacroOpts.data_b
  output_dir = MacroOpts.output_dir
  v_projid = MacroOpts.v_projid

  // Add fields to the output highway layer
  {nlyr, llyr} = GetDBLayers(hwy_o)
  llyr = AddLayerToWorkspace(llyr, hwy_o, llyr)
  /*a_fields = {
    {"tot_proj_length", "Real", 12, 2,,,,"Approximate length of project"},
    {"proj_benefits", "Real", 12, 2,,,,"Approximate length of project"},
    {"score", "Real", 12, 2,,,,"Approximate length of project"}
  }
  RunMacro ("Add Fields", llyr, a_fields, a_initial_values)*/

  // Determine total project lengths
  temp_df = data_b.copy()
  temp_df.filter(params.projid_field + " <> null")
  temp_df.group_by(params.projid_field)
  v_proj_length = if temp_df.get_vector("Dir") <> 0
    then temp_df.get_vector("Length") / 2
    else temp_df.get_vector("Length")
  temp_df.mutate("proj_length", v_proj_length)
  agg = null
  agg.proj_length = {"sum"}
  temp_df.summarize(agg)
  temp_df.rename("sum_proj_length", "tot_proj_length")
  data_b.left_join(temp_df, "ProjID", "ProjID")
  update_df = data_b.copy()
  update_df.select("tot_proj_length")
  update_df.update_view(llyr)

  // Create map of output highway
  opts = null
  opts.file = hwy_o
  {map, {nlyr, llyr}} = RunMacro ("Create Map", opts)

  // Create a distance skim matrix from every node to every node
  Opts = null
  Opts.Input.[Link Set] = {hwy_o + "|" + llyr, llyr}
  Opts.Global.[Network Label] = "network"
  Opts.Global.[Network Options].[Turn Penalties] = "Yes"
  Opts.Global.[Network Options].[Keep Duplicate Links] = "FALSE"
  Opts.Global.[Network Options].[Ignore Link Direction] = "FALSE"
  Opts.Global.[Network Options].[Time Units] = "Minutes"
  Opts.Global.[Link Options].Length = {llyr + ".Length", llyr + ".Length", , , "False"}
  Opts.Global.[Length Units] = "Miles"
  Opts.Global.[Time Units] = "Minutes"
  net_file = output_dir + "/network.net"
  Opts.Output.[Network File] = net_file
  ret = RunMacro("TCB Run Operation", "Build Highway Network", Opts, &Ret)

  Opts = null
  Opts.Input.Network = net_file
  Opts.Input.[Origin Set] = {hwy_o + "|" + nlyr, nlyr}
  Opts.Input.[Destination Set] = {hwy_o + "|" + nlyr, nlyr}
  Opts.Input.[Via Set] = {hwy_o + "|" + nlyr, nlyr}
  Opts.Field.Minimize = "Length"
  Opts.Field.Nodes = nlyr + ".ID"
  Opts.Flag = {}
  Opts.Output.[Output Matrix].Label = "Shortest Path"
  Opts.Output.[Output Matrix].Compression = 1
  mtx_file = output_dir + "/distance.mtx"
  Opts.Output.[Output Matrix].[File Name] = mtx_file
  ret = RunMacro("TCB Run Procedure", "TCSPMAT", Opts, &Ret)

  // Open the matrix, create a currency, and convert
  // nulls (diagonal) to zeros.
  mtx = OpenMatrix(mtx_file, )
  {ri, ci} = GetMatrixIndex(mtx)
  mtx_cores = GetMatrixCoreNames(mtx)
  mtx_cur = CreateMatrixCurrency(mtx, mtx_cores[1], ri, ci, )
  mtx_cur := nz(mtx_cur)

  // Create two node fields on the line layer to display from/to node IDs
  from_node = CreateNodeField(llyr, "from_node", nlyr + ".ID", "From", )
  to_node = CreateNodeField(llyr, "to_node", nlyr + ".ID", "To", )

  /*
  Loop over each project.

  Three sets will be used within the loop:
  project_set
    Selection of links of the current project
  link_set
    Selection of a single link of a project
    (while looping over the proj links)
  link_buffer_set
    Selection of links within the buffer distance around the current proj link

  In addition, the link_set and link_buffer_set also have their nodes selected.
  */
  project_set = RunMacro("G30 create set","current project")
  link_set = RunMacro("G30 create set", "project's link")
  link_set_nodes = RunMacro("G30 create set", "project's link's nodes")
  link_buffer_set = RunMacro("G30 create set", "project's link's buffer")
  link_buffer_set_nodes = RunMacro(
    "G30 create set", "project's link's buffer's nodes"
  )

  data = null

  // Loop over each project
  CreateProgressBar("Secondary Benefit Allocation", "True")
  for p = 1 to v_projid.length do
    proj_id = v_projid[p]
    cancel = UpdateProgressBar(
      "Processing project number " + String(p) +
      " of " + String(v_projid.length),
      R2I((p - 1) / v_projid.length * 100)
    )
    if cancel then do
      DestroyProgressBar()
      DestroyProgressBar()
      Throw("User pressed 'Cancel'")
    end

    // Select the current project
    SetLayer(llyr)
    qry = "Select * where " + params.projid_field + " = " +
      (if TypeOf(proj_id) = "string" then "'" + proj_id + "'"
      else String(proj_id))
    n = SelectByQuery(project_set, "Several", qry)
    if n = 0 then Throw("No project records found")

    // Determine buffer distance
    v_proj_length = GetDataVector(llyr + "|" + project_set, "tot_proj_length", )
    proj_length = v_proj_length[1]
    buffer = proj_length
    buffer = min(buffer, 10)

    // Loop over each link of the current project
    v_proj_link_id = GetDataVector(llyr + "|" + project_set, "ID",)
    CreateProgressBar("Individual Project Links", "True")
    for i = 1 to v_proj_link_id.length do
      id = v_proj_link_id[i]
      cancel = UpdateProgressBar(
        "Processing link number " + String(i) +
        " of " + String(v_proj_link_id.length),
        R2I((i - 1) / v_proj_link_id.length * 100)
      )
      if cancel then do
        DestroyProgressBar()
        DestroyProgressBar()
        Throw("User pressed 'Cancel'")
      end

      // Determine the absolute VMT change on the project link
      // Use absolute VMT change because changes in either direction
      // can induce postive or negative changes on surrounding links.
      // For example, a positive VMT change on a project can create
      // more delay on surrounding links that are now used to feed
      // the project link.  A positive VMT change can also cause a
      // reduction in delay on a parallel facility that now has less
      // traffic.
      rh = LocateRecord(llyr + "|", "ID", {id}, )
      SetRecord(llyr, rh)
      ab_vol_diff = llyr.ab_vol_diff
      ba_vol_diff = llyr.ba_vol_diff
      length = llyr.Length
      vmt_change = abs(ab_vol_diff + ba_vol_diff) * length

      // Select the current link and it's nodes
      SetLayer(llyr)
      qry = "Select * where ID = " + String(id)
      SelectByQuery(link_set, "Several", qry)
      SetLayer(nlyr)
      SelectByLinks(link_set_nodes, "Several", link_set, )

      // Select all links within the buffer distance of the current project
      // link and collect their link IDs.  Don't include links from the
      // current project in the set.  Other projects' links can be included.
      // They may have secondary benefits (mixed benefit type).
      SetLayer(llyr)
      opts = null
      opts.Inclusion = "Intersecting"
      opts.[Source Not] = project_set
      SelectByVicinity(
        link_buffer_set, "Several", llyr + "|" + link_set, buffer, opts
      )

      // Collect ID information on the buffer links and create a table.
      v_buffer_link_ids = GetDataVector(llyr + "|" + link_buffer_set, "ID", opts)
      v_buffer_link_fnode = GetDataVector(
        llyr + "|" + link_buffer_set, "from_node", opts
      )
      v_buffer_link_tnode = GetDataVector(
        llyr + "|" + link_buffer_set, "to_node", opts
      )
      buffer_tbl = null
      buffer_tbl.link_id = v_buffer_link_ids
      buffer_tbl.from_node = v_buffer_link_fnode
      buffer_tbl.to_node = v_buffer_link_tnode

      // Select the buffer link's nodes as well. Allow the current link's
      // nodes to be selected, too.  Distances used are link-to-link, and
      // are calculated by averaging node distances.
      SetLayer(nlyr)
      SelectByLinks(link_buffer_set_nodes, "Several", link_buffer_set, )

      // Create indices for proj link nodes and buffer nodes
      // Delete any that already exist
      a_ind_names = GetMatrixIndexNames(mtx)
      a_ind_names = a_ind_names[1]
      if ArrayPosition(a_ind_names, {"proj_link"}, ) <> 0 then
        DeleteMatrixIndex(mtx, "proj_link")
      link_index = CreateMatrixIndex(
        "proj_link", mtx, "Both", nlyr + "|" + link_set_nodes,
        "ID", "ID"
      )
      if ArrayPosition(a_ind_names, {"buffer_link"}, ) <> 0 then
        DeleteMatrixIndex(mtx, "buffer_link")
      buffer_index = CreateMatrixIndex(
        "buffer_link", mtx, "Both", nlyr + "|" + link_buffer_set_nodes,
        "ID", "ID"
      )

      // Create currencies for each direction of travel (from project link
      // and to project link).
      from_link_cur = CreateMatrixCurrency(
        mtx, mtx_cores[1], link_index, buffer_index,
      )
      to_link_cur = CreateMatrixCurrency(
        mtx, mtx_cores[1], buffer_index, link_index,
      )

      // Get distance vectors from skim matrix.   Collect for both proj nodes
      // and in both directions (4 vectors)
      SetLayer(llyr)
      a_nodes = GetEndpoints(id)
      dist = null
      opts = null
      opts.Index = "Row"
      dist.buffer_node = GetMatrixVector(to_link_cur, opts)
      dist.buffer_node.rowbased  ="True"
      for n = 1 to a_nodes.length do
        node = a_nodes[n]

        opts = null
        opts.Row = node
        dist.("from_" + String(node)) = GetMatrixVector(from_link_cur, opts)
        dist.("from_" + String(node)).rowbased = "True"
        opts = null
        opts.Column = node
        dist.("to_" + String(node)) = GetMatrixVector(to_link_cur, opts)
        dist.("to_" + String(node)).rowbased = "True"
      end

      dist.min_to = min(
        dist.("to_" + String(a_nodes[1])), dist.("to_" + String(a_nodes[2]))
      )
      dist.min_from = min(dist.("from_" + String(a_nodes[1])), dist.("from_" +
        String(a_nodes[2])))
      dist.direction = if dist.min_to < dist.min_from then "to" else "from"
      dist.min_dist = min(dist.min_to, dist.min_from)
      dist.max_dist = if dist.direction = "to"
        then max(dist.("to_" + String(a_nodes[1])), dist.("to_" +
          String(a_nodes[2])))
        else max(dist.("from_" + String(a_nodes[1])), dist.("from_" +
          String(a_nodes[2])))

      // To check/debug the distance table calculations
      dist_df = CreateObject("df", dist)
      if p = 1 and i = 1 and MacroOpts.debug then do
        dist_df.write_csv(
          output_dir + "/debug - distance calc for proj " +
          proj_id + " link 1.csv"
        )
      end

      // Join the dist table to the buffer table twice - once for each node
      // on the buffer link
      // The average distance is calculated from both buffer link nodes to
      // the nearest project node.  This removes bias against long project
      // links.
      dist_df.select({"buffer_node", "min_dist"})
      buffer_df = CreateObject("df", buffer_tbl)
      buffer_df.left_join(dist_df, "from_node", "buffer_node")
      buffer_df.rename("min_dist", "min_dist1")
      buffer_df.left_join(dist_df, "to_node", "buffer_node")
      buffer_df.rename("min_dist", "min_dist2")
      buffer_df.mutate(
        "avg_dist",
        (buffer_df.tbl.min_dist1 + buffer_df.tbl.min_dist2) / 2
      )

      // Create a table with the buffer link ids
      // and their distances to the project link.
      data = null
      data.buffer_link_id = buffer_df.tbl.link_id

      // Collect secondary info and add to table
      ab_sec_ben = GetDataVector(llyr + "|" + link_buffer_set, "ab_sec_ben", )
      ba_sec_ben = GetDataVector(llyr + "|" + link_buffer_set, "ba_sec_ben", )
      sec_ben = ab_sec_ben + ba_sec_ben
      data.secondary_benefit = sec_ben

      // Add other pertinent data
      // Add vmt change
      opts = null

      opts.Constant = proj_id
      type = if TypeOf(proj_id) = "string" then "string" else "Long"
      v_temp = Vector(v_buffer_link_ids.length, type, opts)
      data.proj_id = v_temp

      opts.Constant = id
      v_temp = Vector(v_buffer_link_ids.length, "Long", opts)
      data.proj_link_id = v_temp

      opts.Constant = vmt_change
      v_temp = Vector(v_buffer_link_ids.length, "Double", opts)
      data.vmt_change = v_temp

      opts.Constant = buffer
      v_temp = Vector(v_buffer_link_ids.length, "Double", opts)
      data.buffer = v_temp

      // Add distance and distance decay info
      data.dist2link = buffer_df.tbl.avg_dist
      // Set distance floor to .5 miles.
      data.dist2link = max(data.dist2link, .5)
      // Use (1/dist)^.5
      /*data.dist_weight = Pow(1 / max(.5, v_dist), .5)*/

      // Use (1 - dist / buffer) ^ 4
      data.dist_weight = Pow(1 - data.dist2link / data.buffer, 4)
      /* The average distance could be longer than the buffer for two reasons
      1. The "touching" inclusion setting in SelectByVicinity
      2. The difference between network skim distance and straightline buffer

      If the average distance is larger than the buffer, the dist_weight
      function starts going positive again.  Set it to zero if that happens.
      This prevents that link from contributing any secondary benefits at all.

      In effect, this trims the buffer links down to only those that can
      reach the project link, along the network, within the buffer distance.*/
      data.dist_weight = if data.dist2link > buffer then 0 else data.dist_weight

      // Build the secondary_df table by binding data to it
      // after each loop
      if p = 1 and i = 1 then do
        secondary_df = CreateObject("df", data)
      end else do
        data_df = CreateObject("df", data)
        secondary_df.bind_rows(data_df)
      end
    end
    DestroyProgressBar()
  end

  secondary_df.create_editor()
  RunMacro("Close All")
EndMacro


// Previous code implementing delay allocation method

Macro "old"

    /*
    Secondary benefit allocation
    */

    // Use the tables library to vectorize and write out data
    /*data = RunMacro("Vectorize Table", data)
    RunMacro("Write Table", data, output_dir + "test.csv")*/

    // Use the tables library to apportion benefits
    agg = null
    agg.vmt_change = {"sum"}
    agg.dist_weight = {"sum"}
    summary = RunMacro("Summarize", secondary_df, {"buffer_link_id"}, agg)
    /*summary = RunMacro(
      "Select", {"buffer_link_id", "sum_vmt_change", "sum_DistWeight"}
    )*/
    secondary_df = RunMacro("Join Tables", secondary_df, "buffer_link_id", summary, "buffer_link_id")
    secondary_df.pct_vmt = secondary_df.vmt_change / secondary_df.sum_vmt_change
    secondary_df.pct_distweight = secondary_df.dist_weight / secondary_df.sum_DistWeight
    secondary_df.combined = secondary_df.pct_vmt * secondary_df.pct_distweight

    agg = null
    agg.combined = {"sum"}
    summary2 = RunMacro("Summarize", secondary_df, {"buffer_link_id"}, agg)
    /*summary2 = RunMacro("Select", {"buffer_link_id", "sum_combined"})*/
    secondary_df = RunMacro("Join Tables", secondary_df, "buffer_link_id", summary2, "buffer_link_id")
    secondary_df.pct = secondary_df.combined / secondary_df.sum_combined
    secondary_df.final = secondary_df.pct * secondary_df.secondary_benefit
    // Write out intermediate table for checking
    RunMacro(
      "Write Table", secondary_df,
      output_dir + "check secondary benefit assignment.csv"
    )

    agg = null
    agg.final = {"sum"}
    secondary_tbl = RunMacro("Summarize", secondary_df, {"proj_id"}, agg)
    secondary_tbl = RunMacro(
      "Rename Field", secondary_tbl, "sum_final", "secondary_benefits"
    )
    secondary_tbl.Count = null

    /*
    --------------------------------------------------------------
    Step 3:
    Calculate project-level metrics like VMT change and CMA change
    --------------------------------------------------------------
    */

    // VMT - Vehicle Miles Traveled
    // CMA - Capacity Miles Available (metric made up for this application)
    //       Currently used to calculate utilization
    // Util - "Utilization" or how much of the project is being used
    // Prime - Primary benefits on the project links
    // Change means the difference between build and no-build
    v_projVMTDiff = Vector(v_projid.length,"Float",{{"Constant",0}})
    v_projCMADiff = Vector(v_projid.length,"Float",{{"Constant",0}})
    v_projPrimeBen = Vector(v_projid.length,"Float",{{"Constant",0}})

    for i = 1 to v_projid.length do
      proj_id = v_projid[i]

      // VMT Change
      v_tempVMT = if ( v_allprojid = proj_id ) then v_length * (v_ABVolDiff + v_BAVolDiff) else 0
      vmt = VectorStatistic(v_tempVMT,"Sum",)

      // CMA Change
      v_tempCMA = if ( v_allprojid = proj_id ) then v_length * (v_ABCapDiff + v_BACapDiff) else 0
      cma = VectorStatistic(v_tempCMA,"Sum",)

      v_projVMTDiff[i] = vmt
      v_projCMADiff[i] = cma

      // Primary Benefits
      v_tempBen = if ( v_allprojid = proj_id ) then (v_ab_prim_ben + v_ba_prim_ben) else 0
      primeBen = VectorStatistic(v_tempBen,"Sum",)

      v_projPrimeBen[i] = primeBen
    end

    // Utilization
    v_projUtil = v_projVMTDiff / v_projCMADiff

    // Create a final table object
    a_colNames = {"proj_id", "vmt_diff", "cap_diff",
      "utilization", "primary_benefits"}
    a_data = {v_projid, v_projVMTDiff, v_projCMADiff,
      v_projUtil, v_projPrimeBen}
    RESULT = RunMacro("Create Table", a_colNames, a_data)

    // Join the secondary benefit information to that table
    // and calculate total benefits
    RESULT = RunMacro("Join Tables", RESULT, "proj_id", secondary_tbl, "proj_id")
    RESULT.total_benefits = RESULT.primary_benefits + RESULT.secondary_benefits

    RunMacro(
      "Write Table", RESULT,
      output_dir + "final results.csv"
    )

    // Show warning if the delay increased from no-build to build
    v_totalDelayDiff = v_ab_delay_diff + v_ba_delay_diff
    if VectorStatistic(v_totalDelayDiff,"sum",) > 0 then do
      warningString = "Warning: Total delay increased from no-build " +
        "to build scenarios."
      ShowMessage(warningString)
    end

    DestroyProgressBar()
    ShowMessage("Done calculating benefits")
    quit:

EndMacro

/*
This macro takes an open highway layer (in a map) and a project id.
Exports the project links to a project layer.
Returns a vector describing the distance of every link in the highway layer
from the project layer.  Also appends the information to the highway layer
in field "dist_2_proj".

map
  String
  name of open map

llyr
  String
  Name of highway link layer

set
  String (Optional)
  Name of selection of highway links to calc distance to the project

p_id_field
  String
  Name of the field holding project IDs

proj_id
  String or Integer
  Project ID to calc distance to
*/

Macro "Distance to Project" (map, llyr, set, p_id_field, proj_id)

  SetLayer(llyr)
  qry = "Select * where " + p_id_field + " = " +
    (if TypeOf(proj_id) = "string" then "'" + proj_id + "'"
    else String(proj_id))
  n = SelectByQuery("proj", "Several", qry)
  if n = 0 then Throw("No project records found")

  file = GetTempFileName("*.dbd")
  opts = null
  opts.[Layer Name] = "temp"
  ExportGeography(llyr + "|proj", file, opts)
  {p_nlyr, p_llyr} = GetDBLayers(file)
  AddLayer(map, p_llyr, file, p_llyr)

  a_fields = {{"dist_2_proj", "Real", 10, 2, }}
  RunMacro("TCB Add View Fields", {llyr, a_fields})

  SetLayer(llyr)
  TagLayer("Distance", llyr + "|" + set, "dist_2_proj", p_llyr, )

  v_dist = GetDataVector(llyr + "|" + set, "dist_2_proj", )

  DropLayer(map, p_llyr)
  return(v_dist)
Endmacro

/*
This macro is used to prepare a csv table that can be used to estimate
a distance profile for projects.  A no build scenario is required. Each
comparison sceanrio must be the same as the no-build, but with one
project added.
*/

Macro "Prepare Dist Est File"

  // Prepare arrays of scenario folder names and project IDs.
  // Each scenario (other than no-build) must have one extra project
  // included in addition to any projects in the no-build.
  scen_dir = "C:\\projects/HamptonRoads/Repo/scenarios"
  no_build = "EC2040"
  a_scens = {"SEPG_1", "SEPG_1_8L", "SEPG_2", "SEPG_3", "SEPG_4"}
  a_proj_id = {1001, 1001, 1002, 1003, 1004}

  // Add no_build highway to the workspace before looping over scenarios
  nb_hwy = scen_dir + "/" + no_build + "/Outputs/HR_Highway.dbd"
  {nb_n, nb_l} = GetDBLayers(nb_hwy)
  nb_l = AddLayerToWorkspace("no build", nb_hwy, nb_l)

  // Open a file to write results to and add header row
  file = OpenFile(scen_dir + "/dist_estimation.csv", "w")
  WriteLine(file, "scenario,id,distance,vmt,abs_vmt_diff")

  // Loop over each scenario
  for s = 1 to a_scens.length do
    scen = a_scens[s]
    proj_id = a_proj_id[s]

    // Open a map of the scenario output highway layer
    hwy_file = scen_dir + "/" + scen + "/Outputs/HR_Highway.dbd"
    {nlyr, llyr} = GetDBLayers(hwy_file)
    map = RunMacro("G30 new map", hwy_file)

    // Call the distance to project macro to calculate distances
    p_id_field = "PROJ_ID"
    RunMacro("Distance to Project", map, llyr, set, p_id_field, proj_id)

    // Join no-build layer and collect data
    jv = JoinViews("jv", llyr + ".ID", nb_l + ".ID", )
    opts = null
    opts.[Sort Order] = {{llyr + ".ID", "Ascending"}}
    opts.[Missing as Zero] = "True"
    v_id = GetDataVector(jv + "|", llyr + ".ID", opts)
    v_length = GetDataVector(jv + "|", llyr + ".Length", opts)
    v_dist = GetDataVector(jv + "|", llyr + ".dist_2_proj", opts)
    v_nb_vol = GetDataVector(jv + "|", nb_l + ".TOT_FlowDAY", opts)
    v_vol = GetDataVector(jv + "|", llyr + ".TOT_FlowDAY", opts)

    // Calculate vmt
    v_vmt = v_vol * v_length
    v_nb_vmt = v_nb_vol * v_length

    // Calculate absolute change and absolute percent change in vmt
    v_abs_diff = abs(v_vmt - v_nb_vmt)

    // Write each line of the vectors to a row in the csv
    for i = 1 to v_id.length do
      line = scen + "," + String(v_id[i]) + "," + String(v_dist[i]) +
      "," + String(v_vmt[i]) +
      "," + String(v_abs_diff[i])
      WriteLine(file, line)
    end

    CloseView(jv)
    CloseMap(map)
  end

  CloseFile(file)
  ShowMessage("Done")
EndMacro

/*
Uses a skim matrix curreny and two link IDs and returns the
distance between them.
*/

Macro "Get Dist from Matrix" (a_id, b_id, mtx_cur)

  a_nodes = GetEndpoints(a_id)
  b_nodes = GetEndpoints(b_id)

  min_dist = 1000
  for a = 1 to 2 do
    for b = 1 to 2 do
      dist = GetMatrixValue(mtx_cur, a_nodes[a], b_nodes[b])
      if dist > 0 then min_dist = min(min_dist, dist)
    end
  end

EndMacro

/*
This macro reads the example data and parameters in the GT repository, performs
the delay allocation method, and then checks the results against known answers.
This way, it will be easy to determine if the algorithm is broken by a
modification to the script.

There is no way to automatically locate the location of this script on different
computers without compiling to UI. Instead, modify the 'test_dir' variable
to point to the "unit_test" folder before testing. Try to avoid commiting that
change to the repo.
*/

Macro "da unit test"

  test_dir = "Y:\\projects/gisdk_tools/repo/network_tools/delay_allocation/unit_test"

  RunMacro("Destroy Progress Bars")

  opts = null
  opts.hwy_b = test_dir + "/build_network/build.dbd"
  opts.hwy_nb = test_dir + "/nobuild_network/nobuild.dbd"
  opts.param_file = test_dir + "/parameters.csv"
  opts.output_dir = test_dir + "/output"
  opts.debug = "true"
  RunMacro("Delay Allocation", opts)

  // Delete the output folder after checking results
  // RunMacro("Delete Directory", opts.output_dir)

  ShowMessage("Passed Tests")
EndMacro
