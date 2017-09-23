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

  RunMacro("Close All")
  DestroyProgressBar()
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
    "ID", "Length", params.projid_field,
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
  data_b.mutate("ab_vol_diff", v_abdiff)
  v_badiff = data_b.get_vector(params.ba_vol) - data_nb.get_vector(params.ba_vol)
  data_b.mutate("ba_vol_diff", v_badiff)
  v_totdiff = data_b.get_vector("ab_vol_diff") + data_b.get_vector("ba_vol_diff")
  data_b.mutate("tot_vol_diff", v_totdiff)
  v_abpctdiff = min(999, v_abdiff / (data_nb.get_vector(params.ab_vol) + .0001) * 100)
  data_b.mutate("ab_vol_pct_diff", v_abpctdiff)
  v_bapctdiff = min(999, v_badiff / (data_nb.get_vector(params.ba_vol) + .0001) * 100)
  data_b.mutate("ba_vol_pct_diff", v_bapctdiff)

  // Calculate absolute and pct volume changes from no build to build
  v_abdiff = data_b.get_vector(params.ab_cap) - data_nb.get_vector(params.ab_cap)
  data_b.mutate("ab_cap_diff", v_abdiff)
  v_badiff = data_b.get_vector(params.ba_cap) - data_nb.get_vector(params.ba_cap)
  data_b.mutate("ba_cap_diff", v_badiff)
  v_totdiff = data_b.get_vector("ab_cap_diff") + data_b.get_vector("ba_cap_diff")
  data_b.mutate("tot_cap_diff", v_totdiff)
  v_abpctdiff = min(999, v_abdiff / (data_nb.get_vector(params.ab_cap) + .0001) * 100)
  data_b.mutate("ab_cap_pct_diff", v_abpctdiff)
  v_bapctdiff = min(999, v_badiff / (data_nb.get_vector(params.ba_cap) + .0001) * 100)
  data_b.mutate("ba_cap_pct_diff", v_bapctdiff)
EndMacro


// Previous code implementing delay allocation method

Macro "old"

    // If delay is in minutes, convert to hours
    if Args.Benefits.abDelayUnits = "mins" then do
      v_abABDelay = v_abABDelay / 60
      v_abBADelay = v_abBADelay / 60
      v_nbABDelay = v_nbABDelay / 60
      v_nbBADelay = v_nbBADelay / 60
    end


    // Determine the unique list of project IDs
    Opts = null
    Opts.Unique = "True"
    Opts.Ascending = "False"
    v_uniqueProjID = SortVector(v_allprojid,Opts)
    // Determine which projects change capacity
    // (includes road diets as well as widenings)
    a_projID = null
    for i = 1 to v_uniqueProjID.length do
      curProjID = v_uniqueProjID[i]

      // Get the capacity change for the current project
      v_capCheck = if ( v_allprojid = curProjID ) then v_totCapDiff else 0
      totCapDiff = VectorStatistic(v_capCheck,"sum",)

      // If the project has changed capacity, add it to the list
      // Also, if the proj ID is 0 or null, ignore it.
      if totCapDiff <> 0 then do
        zero = if TypeOf(curProjID) = "string" then "0" else 0
        if curProjID = zero or curProjID = null then continue
        a_projID = a_projID + {curProjID}
      end
    end
    v_projID = A2V(a_projID)

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

    Absolute value is needed because, while capacity and volume are moving in opposite
    direction, you want to know their relative magnitude.

    This metric will determine how much of the change in delay on the project is
    due to the project and how much is the secondary benefit from other projects.

    Example 1: if a link's capacity increases by 20% and it's volume decreases by 10%:
    2/3 of the delay reduction is due to the project.  That is primary benefit.
    1/3 is due to improvements from other projects drawing volume away.  Secondary benefit.

    Example 2: if a link's capacity decreases by 30% and it's volume increases by 10%:
    3/4 of the delay increase is due to the project.
    1/4 is due to changes in other links.
    */

    // For this section of code, ab/ba once again refers to direction (ab is not "all build").
    // Confusing.  Clean up if given time.

    // Determine which cell (from the commented table above) the links fall into.
    v_linkCategory = Vector(v_allprojid.length,"String",)
    v_linkCategory =    if (v_totDelayDiff < 0) then             // Decreased Delay
        (if v_totCapDiff >= 0 then                               // Increased Capacity
          (if v_totVolDiff >= 0 then "Primary" else "Both")      // Increased/Decreased Volume
        else(if v_totCapDiff < 0 then                            // Decreased Capacity
          (if v_totVolDiff >= 0 then "n/a" else "Secondary")     // Increased/Decreased Volume
          )
        )

      else if (v_totDelayDiff >= 0) then                         // Increased Delay
        (if v_totCapDiff >= 0 then                               // Increased Capacity
          (if v_totVolDiff >= 0 then "Secondary" else "n/a")     // Increased/Decreased Volume
        else(if v_totCapDiff < 0 then                            // Decreased Capacity
          (if v_totVolDiff >= 0 then "Both" else "Primary")      // Increased/Decreased Volume
          )
        )
      else null

    // all delay changes on new facilities are primary
    v_linkCategory = if (v_nbABCap + v_nbBACap = 0) then "Primary" else v_linkCategory
    // if capacity doesn't change, all delay changes are secondary
    v_linkCategory = if v_totCapDiff = 0 then "Secondary" else v_linkCategory

    // Calculate the "both" ratios for all links (even though only used for some)
    v_abCapRatio = abs(v_ABCapPctDiff) / ( abs(v_ABCapPctDiff) + abs(v_ABVolPctDiff ))
    v_baCapRatio = abs(v_BACapPctDiff) / ( abs(v_BACapPctDiff) + abs(v_BAVolPctDiff ))
    v_abVolRatio = abs(v_ABVolPctDiff) / ( abs(v_ABCapPctDiff) + abs(v_ABVolPctDiff ))
    v_baVolRatio = abs(v_BAVolPctDiff) / ( abs(v_BACapPctDiff) + abs(v_BAVolPctDiff ))

    // Calculate primary/secondary benefits based on this grouping
    // Multiply the benefit vectors by -1 to change a decrease in delay
    // into a positive benefit metric.
    v_abPrimBen = if v_linkCategory = "Primary" then v_ABDelayDiff * -1 else 0
    v_abPrimBen = if v_linkCategory = "Both" then
      v_ABDelayDiff * -1 * v_abCapRatio else v_abPrimBen
    v_baPrimBen = if v_linkCategory = "Primary" then v_BADelayDiff * -1 else 0
    v_baPrimBen = if v_linkCategory = "Both" then
      v_BADelayDiff * -1 * v_baCapRatio else v_baPrimBen

    v_abSecBen  = if v_linkCategory = "Secondary" then v_ABDelayDiff * -1 else 0
    v_abSecBen  = if v_linkCategory = "Both" then
      v_ABDelayDiff * -1 * v_abVolRatio else v_abSecBen
    v_baSecBen  = if v_linkCategory = "Secondary" then v_BADelayDiff * -1 else 0
    v_baSecBen  = if v_linkCategory = "Both" then
      v_BADelayDiff * -1 * v_baVolRatio else v_baSecBen

    // Check calculation in debug mode
    if Args.General.debug = 1 then do
      path = SplitPath(hwy_b)
      output_dir = path[1] + path[2] + "\\BenefitCalculation\\"
      testCSV = output_dir + "TestLinkCategoryLogic.csv"
      file = OpenFile(testCSV,"w")
      WriteLine(file,"ProjID,nbCap,totDelayDiff,totCapDiff,totVolDiff,Type,abCapRatio,baCapRatio,abVolRatio,baVolRatio,abPrimBen,baPrimBen,abSecBen,baSecBen")
      for i = 1 to v_linkCategory.length do
        pID = v_allprojid[i]
        pID = if TypeOf(pID) <> "string" then String(pID) else pID
        WriteLine(file, pID + "," + String(v_nbABCap[i] + v_nbBACap[i]) + "," + String(v_totDelayDiff[i]) + "," + String(v_totCapDiff[i]) + "," + String(v_totVolDiff[i])
          + "," + v_linkCategory[i] + "," + String(v_abCapRatio[i]) + "," + String(v_baCapRatio[i]) + "," + String(v_abVolRatio[i]) + "," + String(v_baVolRatio[i]) + "," + String(v_abPrimBen[i]) + "," + String(v_baPrimBen[i])
          + "," + String(v_abSecBen[i]) + "," + String(v_baSecBen[i]))
      end
      CloseFile(file)
    end

    // For some reason, these equations can lead to "negative zero"
    // results that sort as smaller than, for example, -80
    // Doesn't make sense - Have to set them to 0
    v_abPrimBen = if ( v_abPrimBen < .0001 and v_abPrimBen > -.0001 ) then 0
      else v_abPrimBen
    v_baPrimBen = if ( v_baPrimBen < .0001 and v_baPrimBen > -.0001 ) then 0
      else v_baPrimBen
    v_abSecBen = if ( v_abSecBen < .0001 and v_abSecBen > -.0001 ) then 0
      else v_abSecBen
    v_baSecBen = if ( v_baSecBen < .0001 and v_baSecBen > -.0001 ) then 0
      else v_baSecBen

    // Modify the structure of the result hwy file
    // to add benefit-related fields
    {nlayer, llayer} = GetDBLayers(hwy_o)
    dv_temp = AddLayerToWorkspace(
      llayer, hwy_o, llayer,
    )
    strct = GetTableStructure(dv_temp)
    for i = 1 to strct.length do
        strct[i] = strct[i] + {strct[i][1]}
    end

    strct = strct + {{"ABCapChange"  , "Real", 12, 2, "False", , ,    "AB Pct Capacity Change on Link", , , , null}}
    strct = strct + {{"BACapChange"  , "Real", 12, 2, "False", , ,    "BA Pct Capacity Change on Link", , , , null}}
    strct = strct + {{"ABPctCapChange"  , "Real", 12, 2, "False", , , "AB Pct Capacity Change on Link", , , , null}}
    strct = strct + {{"BAPctCapChange"  , "Real", 12, 2, "False", , , "BA Pct Capacity Change on Link", , , , null}}
    strct = strct + {{"ABVolChange"  , "Real", 12, 2, "False", , ,    "AB Pct Volume Change on Link", , , , null}}
    strct = strct + {{"BAVolChange"  , "Real", 12, 2, "False", , ,    "BA Pct Volume Change on Link", , , , null}}
    strct = strct + {{"ABPctVolChange"  , "Real", 12, 2, "False", , , "AB Pct Volume Change on Link", , , , null}}
    strct = strct + {{"BAPctVolChange"  , "Real", 12, 2, "False", , , "BA Pct Volume Change on Link", , , , null}}
    // If the delay is discounted for V/C > 1, state that in the description
    if discount <> 1 then do
      strct = strct + {{"ABDelayChange"   , "Real", 12, 2, "False", , , "Discounted AB Delay Change on Link. Delay above V/C = 1 multiplied by " + String(discount), , , , null}}
      strct = strct + {{"BADelayChange"   , "Real", 12, 2, "False", , , "Discounted AB Delay Change on Link. Delay above V/C = 1 multiplied by " + String(discount), , , , null}}
    end else do
      strct = strct + {{"ABDelayChange"   , "Real", 12, 2, "False", , , "Total AB Delay Change on Link", , , , null}}
      strct = strct + {{"BADelayChange"   , "Real", 12, 2, "False", , , "Total BA Delay Change on Link", , , , null}}
    end
    strct = strct + {{"LinkCategory"   , "String", 12, 2, "False", , , "Whether the link benefits are Primary, Secondary, or Both", , , , null}}
    strct = strct + {{"ABPrimBen"       , "Real", 12, 4, "False", , , "Delay savings from improvements to this link", , , , null}}
    strct = strct + {{"BAPrimBen"       , "Real", 12, 4, "False", , , "Delay savings from improvements to this link", , , , null}}
    strct = strct + {{"ABSecBen"        , "Real", 12, 4, "False", , , "Delay savings from improvements to other links", , , , null}}
    strct = strct + {{"BASecBen"        , "Real", 12, 4, "False", , , "Delay savings from improvements to other links", , , , null}}
    strct = strct + {{"ProjectLength"  , "Real", 12, 2, "False", , ,    "The approximate length of the project", , , , null}}
    strct = strct + {{"ProjBens"        , "Real", 12, 4, "False", , , "Total benefits assigned to this project ID", , , , null}}
    strct = strct + {{"Score"        , "Real", 12, 4, "False", , , "Final score of this project ID|Manually filled in", , , , null}}
    ModifyTable(dv_temp, strct)

    // Set the values of the new fields
    SetDataVector(	dv_temp + "|",	"ABCapChange",	v_ABCapDiff	,)
    SetDataVector(	dv_temp + "|",	"BACapChange",	v_BACapDiff	,)
    SetDataVector(	dv_temp + "|",	"ABPctCapChange",	v_ABCapPctDiff	,)
    SetDataVector(	dv_temp + "|",	"BAPctCapChange",	v_BACapPctDiff	,)
    SetDataVector(	dv_temp + "|",	"ABVolChange",	v_ABVolDiff	,)
    SetDataVector(	dv_temp + "|",	"BAVolChange",	v_BAVolDiff	,)
    SetDataVector(	dv_temp + "|",	"ABPctVolChange",	v_ABVolPctDiff	,)
    SetDataVector(	dv_temp + "|",	"BAPctVolChange",	v_BAVolPctDiff	,)
    SetDataVector(	dv_temp + "|",	"ABDelayChange",	v_ABDelayDiff	,)
    SetDataVector(	dv_temp + "|",	"BADelayChange",	v_BADelayDiff	,)
    SetDataVector(	dv_temp + "|",	"LinkCategory",	v_linkCategory	,)
    SetDataVector(	dv_temp + "|",	"ABPrimBen",	v_abPrimBen	,)
    SetDataVector(	dv_temp + "|",	"BAPrimBen",	v_baPrimBen	,)
    SetDataVector(	dv_temp + "|",	"ABSecBen",	v_abSecBen	,)
    SetDataVector(	dv_temp + "|",	"BASecBen",	v_baSecBen	,)





    /*
    Secondary benefit allocation
    */

    // Loop over each project ID and determine the length
    SetLayer(dv_temp)
    for p = 1 to v_projID.length do
      projID = v_projID[p]

      // Some models use strings for project IDs, others don't.  Catch both.
      if Args.Benefits.projIDType = "String" then
        projQuery = "Select * where " + Args.Benefits.projID + " = '" +
        projID + "'"
      else projQuery = "Select * where " + Args.Benefits.projID + " = " +
        String(projID)
      n = SelectByQuery("tempproj","Several",projQuery)

      // Get direction and length vectors
      v_dir = GetDataVector(dv_temp + "|tempproj","Dir",)
      v_lengthTemp = GetDataVector(dv_temp + "|tempproj","Length",)

      // Divide length by 2 if direction <> 0 (to avoid double counting length)
      v_lengthTemp = if v_dir <> 0 then v_lengthTemp / 2 else v_lengthTemp

      // Determine the total project distance and set that value for every
      // link with the same project ID in the network
      projLength = VectorStatistic(v_lengthTemp,"Sum",)
      opts = null
      opts.Constant = projLength
      v_projLength = Vector(v_lengthTemp.length,"Double",opts)
      SetDataVector(dv_temp + "|tempproj","ProjectLength",v_projLength,)
    end
    DeleteSet("tempproj")

    DropLayerFromWorkspace(dv_temp)

    // Create a map of the resulting highway layer
    {map,nlayer,llayer} = RunMacro("Create Highway Map", hwy_o)
    SetLayer(llayer)

    // Create a distance skim matrix from every node to every node
    Opts = null
    Opts.Input.[Link Set] = {hwy_o + "|" + llayer, llayer}
    Opts.Global.[Network Label] = "network"
    Opts.Global.[Network Options].[Turn Penalties] = "Yes"
    Opts.Global.[Network Options].[Keep Duplicate Links] = "FALSE"
    Opts.Global.[Network Options].[Ignore Link Direction] = "FALSE"
    Opts.Global.[Network Options].[Time Units] = "Minutes"
    Opts.Global.[Link Options].Length = {llayer + ".Length", llayer + ".Length", , , "False"}
    Opts.Global.[Length Units] = "Miles"
    Opts.Global.[Time Units] = "Minutes"
    net_file = output_dir + "/network.net"
    Opts.Output.[Network File] = net_file
    ret = RunMacro("TCB Run Operation", "Build Highway Network", Opts, &Ret)

    Opts = null
    Opts.Input.Network = net_file
    Opts.Input.[Origin Set] = {hwy_o + "|" + nlayer, nlayer}
    Opts.Input.[Destination Set] = {hwy_o + "|" + nlayer, nlayer}
    Opts.Input.[Via Set] = {hwy_o + "|" + nlayer, nlayer}
    Opts.Field.Minimize = "Length"
    Opts.Field.Nodes = nlayer + ".ID"
    Opts.Flag = {}
    Opts.Output.[Output Matrix].Label = "Shortest Path"
    Opts.Output.[Output Matrix].Compression = 1
    mtx_file = output_dir + "distance.mtx"
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
    from_node = CreateNodeField(llayer, "from_node", nlayer + ".ID", "From", )
    to_node = CreateNodeField(llayer, "to_node", nlayer + ".ID", "To", )

    /*
    Loop over each project.

    Three sets will be used within the loop:
    projectSet
      Selection of links of the current project
    linkSet
      Selection of a single link of a project
      (while looping over the proj links)
    linkBufferSet
      Selection of links within the buffer distance around the current proj link

    In addition, the linkSet and linkBufferSet also have their nodes selected.
    */
    projectSet = RunMacro("G30 create set","current project")
    linkSet = RunMacro("G30 create set", "project's link")
    linkSet_nodes = RunMacro("G30 create set", "project's link's nodes")
    linkBufferSet = RunMacro("G30 create set", "project's link's buffer")
    linkBufferSet_nodes = RunMacro(
      "G30 create set", "project's link's buffer's nodes"
    )

    DATA = null

    // Loop over each project
    CreateProgressBar("Secondary Benefit Allocation", "True")
    for p = 1 to v_projID.length do
      projID = v_projID[p]
      cancel = UpdateProgressBar(
        "Processing project number " + String(p) +
        " of " + String(v_projID.length),
        R2I((p - 1) / v_projID.length * 100)
      )
      if cancel then do
        DestroyProgressBar()
        DestroyProgressBar()
        Throw("User pressed 'Cancel'")
      end

      // Select the current project
      SetLayer(llayer)
      qry = "Select * where " + Args.Benefits.projID + " = " +
        (if TypeOf(projID) = "string" then "'" + projID + "'"
        else String(projID))
      n = SelectByQuery(projectSet, "Several", qry)
      if n = 0 then Throw("No project records found")

      // Determine buffer distance
      v_proj_length = GetDataVector(llayer + "|" + projectSet, "ProjectLength", )
      proj_length = v_proj_length[1]
      buffer = proj_length
      buffer = min(buffer, 10)

      // Loop over each link of the current project
      v_projLinkID = GetDataVector(llayer + "|" + projectSet, "ID",)
      CreateProgressBar("Individual Project Links", "True")
      for i = 1 to v_projLinkID.length do
        id = v_projLinkID[i]
        cancel = UpdateProgressBar(
          "Processing link number " + String(i) +
          " of " + String(v_projLinkID.length),
          R2I((i - 1) / v_projLinkID.length * 100)
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
        rh = LocateRecord(llayer + "|", "ID", {id}, )
        SetRecord(llayer, rh)
        ab_vol_change = llayer.ABVolChange
        ba_vol_change = llayer.BAVolChange
        length = llayer.Length
        vmt_change = abs(ab_vol_change + ba_vol_change) * length

        // Select the current link and it's nodes
        SetLayer(llayer)
        qry = "Select * where ID = " + String(id)
        SelectByQuery(linkSet, "Several", qry)
        SetLayer(nlayer)
        SelectByLinks(linkSet_nodes, "Several", linkSet, )

        // Select all links within the buffer distance of the current project
        // link and collect their link IDs.  Don't include links from the
        // current project in the set.  Other projects' links can be included.
        // They may have secondary benefits (mixed benefit type).
        SetLayer(llayer)
        opts = null
        opts.Inclusion = "Intersecting"
        opts.[Source Not] = projectSet
        SelectByVicinity(
          linkBufferSet, "Several", llayer + "|" + linkSet, buffer, opts
        )

        // Collect ID information on the buffer links and create a table.
        v_bufferLinkIDs = GetDataVector(llayer + "|" + linkBufferSet, "ID", opts)
        v_bufferLink_fnode = GetDataVector(
          llayer + "|" + linkBufferSet, "from_node", opts
        )
        v_bufferLink_tnode = GetDataVector(
          llayer + "|" + linkBufferSet, "to_node", opts
        )
        buffer_tbl = null
        buffer_tbl.link_id = v_bufferLinkIDs
        buffer_tbl.from_node = v_bufferLink_fnode
        buffer_tbl.to_node = v_bufferLink_tnode

        // Select the buffer link's nodes as well. Allow the current link's
        // nodes to be selected, too.  Distances used are link-to-link, and
        // are calculated by averaging node distances.
        SetLayer(nlayer)
        SelectByLinks(linkBufferSet_nodes, "Several", linkBufferSet, )

        // Create indices for proj link nodes and buffer nodes
        // Delete any that already exist
        a_ind_names = GetMatrixIndexNames(mtx)
        a_ind_names = a_ind_names[1]
        if ArrayPosition(a_ind_names, {"proj_link"}, ) <> 0 then
          DeleteMatrixIndex(mtx, "proj_link")
        link_index = CreateMatrixIndex(
          "proj_link", mtx, "Both", nlayer + "|" + linkSet_nodes,
          "ID", "ID"
        )
        if ArrayPosition(a_ind_names, {"buffer_link"}, ) <> 0 then
          DeleteMatrixIndex(mtx, "buffer_link")
        buffer_index = CreateMatrixIndex(
          "buffer_link", mtx, "Both", nlayer + "|" + linkBufferSet_nodes,
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
        SetLayer(llayer)
        a_nodes = GetEndpoints(id)
        DIST = null
        opts = null
        opts.Index = "Row"
        DIST.buffer_node = GetMatrixVector(to_link_cur, opts)
        DIST.buffer_node.rowbased  ="True"
        for n = 1 to a_nodes.length do
          node = a_nodes[n]

          opts = null
          opts.Row = node
          DIST.("from_" + String(node)) = GetMatrixVector(from_link_cur, opts)
          DIST.("from_" + String(node)).rowbased = "True"
          opts = null
          opts.Column = node
          DIST.("to_" + String(node)) = GetMatrixVector(to_link_cur, opts)
          DIST.("to_" + String(node)).rowbased = "True"
        end

        DIST.min_to = min(DIST.("to_" + String(a_nodes[1])), DIST.("to_" + String(a_nodes[2])))
        DIST.min_from = min(DIST.("from_" + String(a_nodes[1])), DIST.("from_" + String(a_nodes[2])))
        DIST.direction = if DIST.min_to < DIST.min_from then "to" else "from"
        DIST.min_dist = min(DIST.min_to, DIST.min_from)
        DIST.max_dist = if DIST.direction = "to"
          then max(DIST.("to_" + String(a_nodes[1])), DIST.("to_" + String(a_nodes[2])))
          else max(DIST.("from_" + String(a_nodes[1])), DIST.("from_" + String(a_nodes[2])))

        // To check/debug the distance table calculations
        if p = 1 and i = 1
          then RunMacro(
            "Write Table", DIST, output_dir +
            "/check distance calc - proj 1 link 1.csv"
          )

        // Join the DIST table to the buffer table twice - once for each node
        // on the buffer link
        // The average distance is calculated from both buffer link nodes to
        // the nearest project node.  This removes bias against long project
        // links.
        DIST = RunMacro("Select", DIST, {"buffer_node", "min_dist"})
        buffer_tbl = RunMacro("Join Tables", buffer_tbl, "from_node", DIST, "buffer_node")
        buffer_tbl = RunMacro("Rename Field", buffer_tbl, "min_dist", "min_dist1")
        buffer_tbl = RunMacro("Join Tables", buffer_tbl, "to_node", DIST, "buffer_node")
        buffer_tbl = RunMacro("Rename Field", buffer_tbl, "min_dist", "min_dist2")
        buffer_tbl.avg_dist = (buffer_tbl.min_dist1 + buffer_tbl.min_dist2) / 2

        // Create a table with the buffer link ids
        // and their distances to the project link.
        DATA = null
        DATA.BufferLinkID = buffer_tbl.link_id

        // Collect secondary info and add to table
        ABSecBen = GetDataVector(llayer + "|" + linkBufferSet, "ABSecBen", )
        BASecBen = GetDataVector(llayer + "|" + linkBufferSet, "BASecBen", )
        SecBen = ABSecBen + BASecBen
        DATA.SecondaryBenefit = SecBen

        // Add other pertinent data
        // Add vmt change
        opts = null

        opts.Constant = projID
        type = if TypeOf(projID) = "string" then "string" else "Long"
        v_temp = Vector(v_bufferLinkIDs.length, type, opts)
        DATA.projID = v_temp

        opts.Constant = id
        v_temp = Vector(v_bufferLinkIDs.length, "Long", opts)
        DATA.projLinkID = v_temp

        opts.Constant = vmt_change
        v_temp = Vector(v_bufferLinkIDs.length, "Double", opts)
        DATA.vmt_change = v_temp

        opts.Constant = buffer
        v_temp = Vector(v_bufferLinkIDs.length, "Double", opts)
        DATA.buffer = v_temp

        // Add distance and distance decay info
        DATA.dist2link = buffer_tbl.avg_dist
        // Set distance floor to .5 miles.
        DATA.dist2link = max(DATA.dist2link, .5)
        // Use (1/dist)^.5
        /*DATA.DistWeight = Pow(1 / max(.5, v_dist), .5)*/

        // Use (1 - dist / buffer) ^ 4
        DATA.DistWeight = Pow(1 - DATA.dist2link / DATA.buffer, 4)
        /* The average distance could be longer than the buffer for two reasons
        1. The "touching" inclusion setting in SelectByVicinity
        2. The difference between network skim distance and straightline buffer

        If the average distance is larger than the buffer, the DistWeight
        function starts going positive again.  Set it to zero if that happens.
        This prevents that link from contributing any secondary benefits at all.

        In effect, this trims the buffer links down to only those that can
        reach the project link, along the network, within the buffer distance.*/
        DATA.DistWeight = if DATA.dist2link > buffer then 0 else DATA.DistWeight

        // Build the FINAL table by binding DATA to it
        // after each loop
        if p = 1 and i = 1 then do
          FINAL = DATA
        end else do
          FINAL = RunMacro("Bind Rows", FINAL, DATA)
        end
      end

      DestroyProgressBar()
    end

    DestroyProgressBar()

    // Use the tables library to vectorize and write out DATA
    /*DATA = RunMacro("Vectorize Table", DATA)
    RunMacro("Write Table", DATA, output_dir + "test.csv")*/

    // Use the tables library to apportion benefits
    agg = null
    agg.vmt_change = {"sum"}
    agg.DistWeight = {"sum"}
    summary = RunMacro("Summarize", FINAL, {"BufferLinkID"}, agg)
    /*summary = RunMacro(
      "Select", {"BufferLinkID", "sum_vmt_change", "sum_DistWeight"}
    )*/
    FINAL = RunMacro("Join Tables", FINAL, "BufferLinkID", summary, "BufferLinkID")
    FINAL.pct_vmt = FINAL.vmt_change / FINAL.sum_vmt_change
    FINAL.pct_distweight = FINAL.DistWeight / FINAL.sum_DistWeight
    FINAL.combined = FINAL.pct_vmt * FINAL.pct_distweight

    agg = null
    agg.combined = {"sum"}
    summary2 = RunMacro("Summarize", FINAL, {"BufferLinkID"}, agg)
    /*summary2 = RunMacro("Select", {"BufferLinkID", "sum_combined"})*/
    FINAL = RunMacro("Join Tables", FINAL, "BufferLinkID", summary2, "BufferLinkID")
    FINAL.pct = FINAL.combined / FINAL.sum_combined
    FINAL.final = FINAL.pct * FINAL.SecondaryBenefit
    // Write out intermediate table for checking
    RunMacro(
      "Write Table", FINAL,
      output_dir + "check secondary benefit assignment.csv"
    )

    agg = null
    agg.final = {"sum"}
    secondary_tbl = RunMacro("Summarize", FINAL, {"projID"}, agg)
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
    v_projVMTDiff = Vector(v_projID.length,"Float",{{"Constant",0}})
    v_projCMADiff = Vector(v_projID.length,"Float",{{"Constant",0}})
    v_projPrimeBen = Vector(v_projID.length,"Float",{{"Constant",0}})

    for i = 1 to v_projID.length do
      projID = v_projID[i]

      // VMT Change
      v_tempVMT = if ( v_allprojid = projID ) then v_length * (v_ABVolDiff + v_BAVolDiff) else 0
      vmt = VectorStatistic(v_tempVMT,"Sum",)

      // CMA Change
      v_tempCMA = if ( v_allprojid = projID ) then v_length * (v_ABCapDiff + v_BACapDiff) else 0
      cma = VectorStatistic(v_tempCMA,"Sum",)

      v_projVMTDiff[i] = vmt
      v_projCMADiff[i] = cma

      // Primary Benefits
      v_tempBen = if ( v_allprojid = projID ) then (v_abPrimBen + v_baPrimBen) else 0
      primeBen = VectorStatistic(v_tempBen,"Sum",)

      v_projPrimeBen[i] = primeBen
    end

    // Utilization
    v_projUtil = v_projVMTDiff / v_projCMADiff

    // Create a final table object
    a_colNames = {"proj_id", "vmt_diff", "cap_diff",
      "utilization", "primary_benefits"}
    a_data = {v_projID, v_projVMTDiff, v_projCMADiff,
      v_projUtil, v_projPrimeBen}
    RESULT = RunMacro("Create Table", a_colNames, a_data)

    // Join the secondary benefit information to that table
    // and calculate total benefits
    RESULT = RunMacro("Join Tables", RESULT, "proj_id", secondary_tbl, "projID")
    RESULT.total_benefits = RESULT.primary_benefits + RESULT.secondary_benefits

    RunMacro(
      "Write Table", RESULT,
      output_dir + "final results.csv"
    )

    // Show warning if the delay increased from no-build to build
    v_totalDelayDiff = v_ABDelayDiff + v_BADelayDiff
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

  opts = null
  opts.hwy_b = test_dir + "/build_network/build.dbd"
  opts.hwy_nb = test_dir + "/nobuild_network/nobuild.dbd"
  opts.param_file = test_dir + "/parameters.csv"
  opts.output_dir = test_dir + "/output"
  RunMacro("Delay Allocation", opts)

  // Delete the output folder after checking results
  RunMacro("Delete Directory", opts.output_dir)

  ShowMessage("Passed Tests")
EndMacro
