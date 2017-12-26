/*

*/

Macro "Mode Choice NLM" (MacroOpts)

  // Argument extraction
  period = MacroOpts.period
  tables = MacroOpts.tables
  matrices = MacroOpts.matrices
  template_mdl = MacroOpts.template_mdl
  param_file = MacroOpts.param_file
  output_dir = MacroOpts.output_dir

// FOR TESTING ONLY
// Point to the version-controlled template and parameters
dir = "Y:\\projects/NORPC/repo/Scenarios/_base_scenario_dont_modify_taz_change/Reference/mc_dct_files"
template_mdl = dir + "/norpc_mc.mdl"
param_file = dir + "/mc_parameters.csv"

  // Read in the parameter file
  mc_params = RunMacro("Read Parameter File", param_file)
  num_purposes = mc_params.length

  for p = 1 to num_purposes do
    purp = mc_params[p][1]
    prefix = period + "_" + purp

    purp_params = mc_params.(purp)
    num_markets = purp_params.length

    // Create a copy of the template mdl file and update its
    // attributes.
    mdl = output_dir + "/" + prefix + ".mdl"
    CopyFile(template_mdl, mdl)

    // Create model object.
    model = null
    model = CreateObject("NLM.Model")
    model.Read(mdl, 1)

    // Update matrix sources and indices. This also begins building
    // the 'nle_opts' options array for the NestedLogitEngine macro.
    for matrix in matrices do
      source_name = matrix[1]
      opts = matrix[2]
      source = model.Sources.Get(source_name) // The name of the source, as it appears in the MDL/DCM file
      /* source.FileLabel = prefix + " " + source_name // not sure if this has to matc */
      source.RowIdx = opts.index
      source.ColIdx = opts.index
      nle_opts.Input.(source_name + " Matrix") = opts.file
    end

    // Setup the table inputs for NLE
    for table in tables do
      source_name = table[1]
      opts = table[2]
      opts.query = RunMacro("Normalize Query", opts.query)
      {drive, directory, name, ext} = SplitPath(opts.file)
      nle_opts.Input.(source_name + " Set") = {
        opts.file, name, opts.set_name, opts.query
      }
    end

    // Update coefficients and ASCs for each market segment
    for m = 1 to num_markets do
      market = purp_params[m][1]

      params = purp_params.(market)

      // If there is only 1 market segment, it must be named "*" in the
      // template.mdl file.
      if num_markets = 1
        then seg = model.GetSegment("*")
        else seg = model.GetSegment(market)

      // Change coefficients
      coeffs = params.coeffs
      for fld = 1 to model.GetFieldCount() do
        field = model.GetField(fld)
        term = seg.GetTerm(field.Name)
        term.Coeff = nz(coeffs.(field.Name))
      end

      // Change alternative specific constant
      ascs = params.asc
      for a = 1 to seg.GetAlternativeCount() do
        alt = seg.GetAlternative(a)
        asc = nz(ascs.(alt.Name))
        if asc <> 0 then do
          seg.CreateAscTerm(alt)
          term = alt.ASC
          term.Coeff = ascs.(alt.Name)
        end
      end
    end

    // write out the new mdl file for manual review
    model.Write(mdl)
    model.Clear()
  Throw()
    // Finish setup of NestedLogitEngine's options array
    nle_opts.Global.Model = mdl
    nle_opts.Global.[Missing Method] = "Drop Mode"
    nle_opts.Global.[Base Method] = "On Matrix"
    nle_opts.Global.[Small Volume To Skip] = 0.001
    nle_opts.Global.[Utility Scaling] = "By Parent Theta"
    /* nle_opts.Global.ShadowIterations = 10
    nle_opts.Global.ShadowTolerance = 0.001
    nle_opts.Flag.ShadowPricing = 0 */
    nle_opts.Flag.[To Output Utility] = 1
    nle_opts.Flag.[To Output Logsum] = 1
    nle_opts.Flag.Aggregate = 1
    // Probability matrix
    file_name = "probabilities_" + prefix + ".MTX"
    file_path = output_dir + "/" + file_name
    nle_opts.Output.[Probability Matrix].Label = prefix + " Probability"
    nle_opts.Output.[Probability Matrix].Compression = 1
    nle_opts.Output.[Probability Matrix].FileName = file_name
    nle_opts.Output.[Probability Matrix].[File Name] = file_path
    // Utility matrix
    file_name = "utilities_" + prefix + ".MTX"
    file_path = output_dir + "/" + file_name
    nle_opts.Output.[Utility Matrix].Label = prefix + " Utility"
    nle_opts.Output.[Utility Matrix].Compression = 1
    nle_opts.Output.[Utility Matrix].FileName = file_name
    nle_opts.Output.[Utility Matrix].[File Name] = file_path
    // Logsum matrix
    file_name = "logsums_" + prefix + ".MTX"
    file_path = output_dir + "/" + file_name
    nle_opts.Output.[Logsum Matrix].Label = prefix + " Utility"
    nle_opts.Output.[Logsum Matrix].Compression = 1
    nle_opts.Output.[Logsum Matrix].FileName = file_name
    nle_opts.Output.[Logsum Matrix].[File Name] = file_path

    // Run model
    ret_value = RunMacro("TCB Run Procedure", "NestedLogitEngine", nle_opts, &Ret)
  end

  RunMacro("Close All")
EndMacro
