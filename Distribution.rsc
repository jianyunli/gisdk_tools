/*
This script contains three primary functions along with helper macros:
  Gravity
  Destination Choice
  Aggregate Distribution Matrices
*/

/*
Gravity

Depends
  ModelUtilities.rsc
    "Read Parameter File"
*/

Macro "Gravity" (MacroOpts)

  se_bin = MacroOpts.se_bin
  skim_file = MacroOpts.skim_file
  param_file = MacroOpts.param_file
  period = MacroOpts.period
  output_dir = MacroOpts.output_dir

  // Read the parameter file
  grav_params = RunMacro("Read Parameter File", param_file)

  // Open the skim matrix and se table
  skim_mtx = OpenMatrix(skim_file, )
  {ri, ci} = GetMatrixIndex(skim_mtx)
  vw_se = OpenTable("ScenarioSE", "FFB", {se_bin})

  // Loop over each purpose found in the param file
  for p = 1 to grav_params.length do
    purp = grav_params[p][1]

    params = grav_params.(purp).(period)

    // Create skim currency
    imp_core = params.imp_core
    cur = CreateMatrixCurrency(skim_mtx, imp_core, ri, ci, )

    Opts = null
    Opts.Input.[PA View Set] = {se_bin, vw_se}
    Opts.Input.[FF Tables] = {}
    Opts.Input.[Imp Matrix Currencies] = {cur}
    Opts.Input.[FF Matrix Currencies] = {}
    Opts.Global.[Constraint Type] = {params.constraint}
    Opts.Global.[Purpose Names] = {purp}
    Opts.Global.Iterations = {50}
    Opts.Global.Convergence = {0.001}
    Opts.Global.[Fric Factor Type] = {"Gamma"}
    Opts.Global.[A List] = {params.a}
    Opts.Global.[B List] = {params.b}
    Opts.Global.[C List] = {params.c}
    Opts.Global.[Minimum Friction Value] = {0}
    Opts.Field.[Prod Fields] = {params.p_field}
    Opts.Field.[Attr Fields] = {params.a_field}
    Opts.Field.[FF Table Times] = {}
    Opts.Field.[FF Table Fields] = {}
    Opts.Output.[Output Matrix].Label = purp + " Gravity Matrix"
    Opts.Output.[Output Matrix].Compression = 1
    out_file = output_dir + "/trips_" + purp + "_" + period + ".mtx"
    Opts.Output.[Output Matrix].[File Name] = out_file
    ret_value = RunMacro("TCB Run Procedure", "Gravity", Opts, &Ret)
    if !ret_value then Throw("Gravity model failed")
  end
EndMacro

/*
Destination Choice
This DC function uses the NestedLogitEngine in TC.

The object name is "NLM.Model".  You can use GetClassMethodNames("NLM.Model") to
see all the methods available, but there is no help for them.  Caliper has
been willing to help explain some of them and how to use them.

The production and attraction field names are assumed to be in the se_bin file
and use the following general format:
  "d_" + purp + "(a)_" + tod
  e.g.
  d_HBW_AM    (prod field)
  d_HBWa_AM   (attr field)

The remaining information about model specification comes from the
dc_parameters.csv and template.dcm files.

MacroOpts
  period
    String
    Time period - e.g. "AM"

  se_bin
    String
    Path of the se table

  skim_file
    String
    Path to the skim mtx file
    Must include core names referenced by param_file and template_dcm

  output_dir
    String
    Path of the folder to place output

  param_file
    String
    Path to the parameters csv file

  template_dcm
    String
    Path to the template dcm file

  se_set_name
    Optional String
    If running DC on a subset of zones, use this to state the name of the
    selection set. Must match what is listed in the template_dcm. If provided,
    both se_set_name and se_set_query are required.

  se_set_query
    Optional String
    If running DC on a subset of zones, use this to define the selection set.
    e.g. "InternalZone = 'Internal'" or "ID < 2000". If provided,
    both se_set_name and se_set_query are required.


Depends
  ModelUtilities.rsc
    "Read Parameter File"
*/

Macro "Destination Choice" (MacroOpts)

  // Extract arguments from named array
  period = MacroOpts.period
  se_bin = MacroOpts.se_bin
  output_dir = MacroOpts.output_dir
  param_file = MacroOpts.param_file
  template_dcm = MacroOpts.template_dcm
  skim_file = MacroOpts.skim_file
  se_set_name = MacroOpts.se_set_name
  se_set_query = MacroOpts.se_set_query

  // Argument checks
  if period = null then Throw("'period' not provided")
  if se_bin = null then Throw("'se_bin' not provided")
  if output_dir = null then Throw("'output_dir' not provided")
  if param_file = null then Throw("'param_file' not provided")
  if template_dcm = null then Throw("'template_dcm' not provided")
  if skim_file = null then Throw("'skim_file' not provided")
  if se_set_name <> null and se_set_query = null
    then Throw("'se_set_name' and 'se_set_query' must both be provided.")
  if se_set_name = null and se_set_query <> null
    then Throw("'se_set_name' and 'se_set_query' must both be provided.")
  if se_set_query <> null
    then se_set_query = RunMacro("Normalize Query", se_set_query)

  // Read in the dc parameter file
  dc_params = RunMacro("Read Parameter File", param_file)
  num_purposes = dc_params.length

  // Open the se_bin file and add a dc_size and shadow price column
  se_tbl = OpenTable("ScenarioSE", "FFB", {se_bin})
  a_fields = {
    {"dc_size", "Real", 10, 2,,,,"dc size term|varies by purp and tod"},
    {"shadow_price", "Real", 10, 2,,,,"dc shadow price|varies by purp and tod"}
  }
  RunMacro("TCB Add View Fields", {se_tbl, a_fields})
  CloseView(se_tbl)

  for p = 1 to num_purposes do
    purp = dc_params[p][1]

    params = dc_params.(purp).(period)
    max_iters = if (params.max_iters = null) then 1 else params.max_iters
    params.max_iters = null
    // if iterating shadow price, set a min number of iterations
    if max_iters > 1 then min_iters = min(10, max_iters)
    prod_field = "d_" + purp + "_" + period
    attr_field = "d_" + purp + "a_" + period

    // Fill dc_size column with appropriate attraction info
    // Fill shadow price with 0s
    se_tbl = OpenTable("ScenarioSE", "FFB", {se_bin})
    v_attr = nz(GetDataVector(se_tbl + "|", attr_field, ))
    v_attr = if (v_attr = 0) then 0 else log(v_attr)
    SetDataVector(se_tbl + "|", "dc_size", v_attr, )
    v_sp = if (nz(v_attr) >= 0) then 0 else 0
    SetDataVector(se_tbl + "|", "shadow_price", v_sp, )
    CloseView(se_tbl)

    // Calculate a capped distance cores required by DC
    RunMacro("Calc DC Matrix Cores", params.dist_cap, skim_file, period)

    // Create a copy of the template dcm file and update its
    // attributes.
    dcm = output_dir + "/" + purp + "_" + period + ".dcm"
    CopyFile(template_dcm, dcm)

    // Create model object.  The segment is always "*"
    model = null
    model = CreateObject("NLM.Model")
    model.Read(dcm, 1)
    seg = model.GetSegment("*")

    // Change totals field (the productions)
    source = model.Sources.Get("zone_tbl") // name of se table in template dcm
    da = source.CreateDataAccess("totals", prod_field, )
    seg.SetTotals(da)

    // Change coefficients
    for fld = 1 to model.GetFieldCount() do
      field = model.GetField(fld)
      term = seg.GetTerm(field.Name)
      term.Coeff = nz(params.(field.Name))
    end

    // write out the new dcm file for manual review
    model.Write(dcm)
    model.Clear()

    // Run the model
    dc_iter = 1
    pct_rmse = 100
    rmse_target = 5 // percent
    while pct_rmse > rmse_target and dc_iter <= max_iters do
      Opts = null
      Opts.Global.[Missing Method] = "Drop Mode"
      Opts.Global.[Base Method] = "On View"
      Opts.Global.[Small Volume To Skip] = 0.001
      Opts.Global.[Utility Scaling] = "None"
      Opts.Global.Model = dcm
      Opts.Flag.[To Output Utility] = 1
      Opts.Flag.Aggregate = 1
      Opts.Flag.[Destination Choice] = 1
      Opts.Input.[skim_mtx Matrix] = skim_file
      Opts.Input.[zone_tbl Set] = {se_bin, "ScenarioSE", se_set_name, se_set_query}
      // Probability matrix
      file_name = "probabilities_" + purp + "_" + period + ".MTX"
      file_path = output_dir + "/" + file_name
      Opts.Output.[Probability Matrix].Label = purp + " " + period + " Probability"
      Opts.Output.[Probability Matrix].Compression = 1
      Opts.Output.[Probability Matrix].FileName = file_name
      Opts.Output.[Probability Matrix].[File Name] = file_path
      // Trips matrix
      trip_file = "trips_" + purp + "_" + period + ".MTX"
      trip_path = output_dir + "/" + trip_file
      Opts.Output.[Applied Totals Matrix].Label = purp + " " + period + " Trips"
      Opts.Output.[Applied Totals Matrix].Compression = 1
      Opts.Output.[Applied Totals Matrix].FileName = trip_file
      Opts.Output.[Applied Totals Matrix].[File Name] = trip_path
      // Utility matrix
      file_name = "utilities_" + purp + "_" + period + ".MTX"
      file_path = output_dir + "/" + file_name
      Opts.Output.[Utility Matrix].Label = purp + " " + period + " Utility"
      Opts.Output.[Utility Matrix].Compression = 1
      Opts.Output.[Utility Matrix].FileName = file_name
      Opts.Output.[Utility Matrix].[File Name] = file_path

      ret_value = RunMacro("TCB Run Procedure", "NestedLogitEngine", Opts, &Ret)
      if !ret_value then do
        error = Ret[1][1]
        if Left(error, 17) = "Cannot create key" then do
        err_parts = SplitString(error)
        proper_set_name = err_parts[2]
          Throw(
            "The selection set named used in the script ('" + se_set_name + "')\n" +
            "does not match the one used during the template (.dcm) creation\n" +
            "('" + proper_set_name + "')"
          )
        end else Throw("Destination choice model failed")

      end

      // Export column marginals to table
      m = OpenMatrix(trip_path,)
      mc = CreateMatrixCurrency(m,,,,)
      marginal_bin = output_dir + "/marginal.bin"
      ExportMatrix(mc,, "Columns", "FFB", marginal_bin, {{"Marginal", "Sum"}})
      mc = null
      m = null

      // Open matrix marginal table table and join to the se table
      vw_se = OpenTable("se", "FFB", {se_bin})
      vw_marg = OpenTable("temp", "FFB", {marginal_bin,},)
      {flds, specs} = GetFields(vw_marg,)
      SetView(vw_se)
      vw_join = JoinViews("jv", vw_se + ".ID", vw_marg + "." + flds[1],)
      SetView(vw_join)
      qry = "Select * where " + vw_se + "." + attr_field + " > 0"
      n = SelectByQuery("selection", "several", qry)

      // Calculate RMSE
      v_target = GetDataVector(vw_join + "|", vw_se + "." + attr_field, )
      v_result = GetDataVector(vw_join + "|", vw_marg + "." + flds[2], )
      {rmse, pct_rmse} = RunMacro("Calculate Vector RMSE", v_target, v_result)

      // Calculate shadow price
      v_sp = nz(GetDataVector(vw_join + "|", vw_se + ".shadow_price", ))
      v_sp = v_sp + log(v_target / v_result)
      SetDataVector(vw_join + "|", vw_se + ".shadow_price", v_sp, )
      CloseView(vw_join)
      CloseView(vw_se)
      CloseView(vw_marg)

      // Require the min_iters be performed
      if dc_iter < min_iters then pct_rmse = 100
      dc_iter = dc_iter + 1

      // To simplify project code using this macro, never let the final trip matrix
      // have fewer rows/columns than all centroids. Thus, if a selection set was
      // applied, expand the matrix. The new rows/columns will be null.
      if se_set_name <> null then do

        // Copy the skim matrix structure to a temp file
        skim_mtx = OpenMatrix(skim_file, )
        a_skim_mcs = CreateMatrixCurrencies(skim_mtx, , , )
        temp_file = output_dir + "/temp.mtx"
        opts = null
        opts.[File Name] = temp_file
        opts.Label = purp + " " + period + " Trips"
        opts.Type = "Float"
        opts.Tables = {a_skim_mcs[1][1]}
        CopyMatrixStructure({a_skim_mcs[1][2]}, opts)


        // Transfer data
        trip_mtx = OpenMatrix(trip_path, )
        a_trip_mcs = CreateMatrixCurrencies(trip_mtx, , , )
        temp_mtx = OpenMatrix(temp_file, )
        a_temp_mcs = CreateMatrixCurrencies(temp_mtx, , , )
        a_temp_mcs[1][2] := 0
        MergeMatrixElements(a_temp_mcs[1][2], {a_trip_mcs[1][2]}, , , )
        SetMatrixCoreName(temp_mtx, a_skim_mcs[1][1], "Total")

        // Change the row/col index to match
        {ri, ci} = GetMatrixIndex(trip_mtx)
        {temp_ri, temp_ci} = GetMatrixIndex(temp_mtx)
        SetMatrixIndexName(temp_mtx, temp_ri, ri)
        SetMatrixIndexName(temp_mtx, temp_ci, ci)

        // Clean up workspace and replace dc output matrix with temp
        skim_mtx = null
        a_skim_mcs = null
        a_trip_mcs = null
        trip_mtx = null
        temp_mtx = null
        a_temp_mcs = null
        DeleteFile(trip_path)
        RenameFile(temp_file, trip_file)
      end
    end
  end

  // Clean up workspace
  se_tbl = OpenTable("se", "FFB", {se_bin})
  RunMacro("Remove Field", se_tbl, "dc_size")
  RunMacro("Remove Field", se_tbl, "shadow_price")
  CloseView(se_tbl)
  DeleteFile(marginal_bin)
  DeleteFile(Substitute(marginal_bin, ".bin", ".DCB", ))
EndMacro

/*
Helper macro
Adds additional matrix cores needed by DC to the skim file.
For distance polynomial cores, respects the distance cap if provided.
*/

Macro "Calc DC Matrix Cores" (dist_cap, skim_file, period)

  if dist_cap = null then dist_cap = 1000

  // Open matrix and modify cores
  mtx = OpenMatrix(skim_file, )
  a_corenames = GetMatrixCoreNames(mtx)

  // Add new cores used by DC models
  a_new_cores = {
    "dist_cap",
    "dist_sq",
    "dist_cu",
    "dist_const",
    "intrazonal"
  }
  for nc = 1 to a_new_cores.length do
    if ArrayPosition(a_corenames, {a_new_cores[nc]}, ) = 0 then
      AddMatrixCore(mtx, a_new_cores[nc])
  end

  // Create currencies
  {ri, ci} = GetMatrixIndex(mtx)
  cur = CreateMatrixCurrencies(mtx, ri, ci, )

  // Calculate distance polynomial cores based on
  // potentially capped distances.
  cur.dist_cap := min(cur.dist, dist_cap)
  cur.dist_sq := Pow(cur.dist_cap, 2)
  cur.dist_cu := Pow(cur.dist_cap, 3)
  cur.dist_const := 1

  // Calcualte the intrazonal core
  cur.intrazonal := 0
  rows = cur.(cur[1][1]).Rows
  opts = null
  opts.Constant = 1
  v_iz = Vector(rows, "Long", opts)
  opts = null
  opts.Diagonal = "True"
  SetMatrixVector(cur.intrazonal, v_iz, opts)

  cur = null
  mtx = null
EndMacro

/*
Combines distribution output matrices
Creates a single matrix for the time period.  The matrix has a core
for each purpose.

The distribution output matrices to aggregate must follow the naming convention
used by the other macros in this library:
  "trips_" + purp + "_" + period + ".mtx"
  e.g. "trips_HBW_AM.mtx" or "trips_CV_Daily.mtx"

MacroOpts
  Named array containing all arguments for the function

  params
    String or array of strings
    Path(s) of parameter file(s) used by the distribution macros.
    Used to collect all purpose names to combine.

  period
    String
    Time of day to aggregate.

  dir
    String
    Path to the folder containing the output distribution matrices.
    The combined matrix will also be placed here.

Returns
  Nothing
  Creates a matrix in "dir" named
  "_trips_all_" + period + ".mtx"
  e.g. "_trips_all_AM.mtx"
*/

Macro "Aggregate Distribution Matrices" (MacroOpts)

  params = MacroOpts.params
  if TypeOf(params) = "string" then params = {params}
  if TypeOf(params) <> "array"
    then Throw("'params' must be a string or array of strings")
  period = MacroOpts.period
  output_dir = MacroOpts.output_dir
  final_mtx_file = output_dir + "/_trips_all_" + period + ".mtx"

  // Collect purposes from the param files
  for p = 1 to params.length do
    param = params[p]
    vw_p = OpenTable("params", "CSV", {param})
    v_purps = GetDataVector(vw_p + "|", "Purpose", )
    opts = null
    opts.Unique = "True"
    v_purps = SortVector(v_purps, opts)
    a_purps = a_purps + V2A(v_purps)
  end
  CloseView(vw_p)

  // Check to make sure all purposes from the parameter files were unique.
  // For example, if two parameter files had purpose "HBW", that will cause
  // problems.
  opts = null
  opts.Unique = "True"
  a_test = SortArray(a_purps, opts)
  if a_test.length <> a_purps.length
    then Throw("Parameter files have duplicate purpose names")

  for p = 1 to a_purps.length do
    purp = a_purps[p]

    // Open matrix and create currency of first core
    cur_mtx_file = output_dir + "/trips_" + purp + "_" + period + ".mtx"
    mtx = OpenMatrix(cur_mtx_file, )
    {ri, ci} = GetMatrixIndex(mtx)
    a_corenames = GetMatrixCoreNames(mtx)
    corename = a_corenames[1]
    cur = CreateMatrixCurrency(mtx, corename, ri, ci, )

    // set name of new core in final matrix
    fin_corename = purp

    // Copy and format first matrix
    // Add other matrix cores after that
    if p = 1 then do
      opts = null
      opts.[File Name] = final_mtx_file
      opts.Label = period + " distributed trips"
      opts.Cores = {1}
      CopyMatrix(cur, opts)

      fin_mtx = OpenMatrix(final_mtx_file, )
      {f_ri, f_ci} = GetMatrixIndex(mtx)
      a_corenames = GetMatrixCoreNames(fin_mtx)
      if a_corenames[1] <> fin_corename
        then SetMatrixCoreName(fin_mtx, a_corenames[1], fin_corename)
    end else do
      AddMatrixCore(fin_mtx, fin_corename)
      fin_cur = CreateMatrixCurrency(fin_mtx, fin_corename, f_ri, f_ci, )
      fin_cur := cur
    end

    // Delete the individual matrix file after use
    mtx = null
    cur = null
    DeleteFile(cur_mtx_file)
  end

  RunMacro("Close All")
EndMacro
