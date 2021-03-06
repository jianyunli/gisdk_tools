/*
Script Notes:
This script file contains macros that apply the Nested Logit Engine in TransCAD
as well as some utility scripts that support manipulation of .mdl files.
*/

/*
Inputs
  MacroOpts
    period
      String
      Time of day - e.g. "AM" or "PK". Must match a period in the param_file.

    tables
      Named array
      Defines the file and (optional) selection set to use for each table data
      source.

      For example:
        tables.zone_tbl.file = se_bin
        tables.zone_tbl.set_name = "internal"
        tables.zone_tbl.query = "Select * where parish <> 'Ext'"

        where "zone_tbl" is the name of one of the table data sources in the
        template_mdl file.

    matrices
      Named array
      Defines the file and (optional) index to use for each matrix data source.
      Must be nested by matrix names that match those in the template_mdl file.

      For example:
        matrices.hwy_skim.file = ".../skim.mtx"
        matrices.hwy_skim.index = "internal"

        where "hwy_skim" is the name of one of the matrix data sources in the
        template_mdl file.

    template_mdl
      String
      Path to the template model file (.mdl) to use. This file has the nesting
      structure defined as well as the matrix cores and table fields that each
      alternative will use to calculate utilities. The coefficients are usually
      set to 0, as they are overwritten by the parameter file. The nesting
      coefficients are also defined in this file.

    param_file
      String
      Path to the parameter file. This file contains the utility coefficients
      and alternative-specific constants. It is specified by time period,
      purpose, and market segment.

      For Example:
        Period | Purpose | Segment| Section | Term     | Value | Description
        PK     | HBW     | inc1   | coeffs  | init_wait| -.2   | initial wait time
        PK     | HBW     | inc1   | asc     | wEB      | -1.2  | ASC for walk-to-express-bus
        etc

    output_dir
      String
      Path to the output directory. This is the folder where all outputs will
      be stored.

    combine_outputs
      Optional True/False
      If true (default), all output matrices from MC will be combined into
      a single matrix for each period.
*/

Macro "GT - Mode Choice NLM" (MacroOpts)

  // Argument extraction
  period = MacroOpts.period
  tables = MacroOpts.tables
  matrices = MacroOpts.matrices
  template_mdl = MacroOpts.template_mdl
  param_file = MacroOpts.param_file
  output_dir = MacroOpts.output_dir
  combine_outputs = MacroOpts.combine_outputs

  if combine_outputs = null then combine_outputs = "true"

  // Read in the parameter file
  mc_params = RunMacro("Read Parameter File", param_file)
  period_params = mc_params.(period)
  num_purposes = period_params.length

  for p = 1 to num_purposes do
    purp = period_params[p][1]
    prefix = period + "_" + purp

    purp_params = period_params.(purp)
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
    nle_opts = null
    for matrix in matrices do
      source_name = matrix[1]
      opts = matrix[2]
      // The name of the source, as it appears in the MDL/DCM file
      source = model.Sources.Get(source_name)
      if opts.index <> null then do
        source.RowIdx = opts.index
        source.ColIdx = opts.index
      end
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

      nle_opts.Global.Segments = nle_opts.Global.Segments + {market}

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

    // Finish setup of NestedLogitEngine's options array
    nle_opts.Global.Model = mdl
    nle_opts.Global.[Missing Method] = "Drop Mode"
    nle_opts.Global.[Base Method] = "On Matrix"
    /* nle_opts.Global.[Base Method] = "On View" */
    nle_opts.Global.[Small Volume To Skip] = 0.001
    nle_opts.Global.[Utility Scaling] = "By Parent Theta"
    nle_opts.Global.ShadowIterations = 10
    nle_opts.Global.ShadowTolerance = 0.001
    nle_opts.Flag.ShadowPricing = 0
    nle_opts.Flag.[To Output Utility] = 1
    nle_opts.Flag.[To Output Logsum] = 1
    nle_opts.Flag.Aggregate = 1
    // An output matrix is created for each market
    prob_mtxs = null
    util_mtxs = null
    logsum_mtxs = null
    for m = 1 to num_markets do
      market = purp_params[m][1]

      file_name = "probabilities_" + prefix + "_" + market + ".MTX"
      file_path = output_dir + "/" + file_name
      opts = null
      opts.Label = prefix + "_" + market + " Probability"
      opts.Compression = 1
      opts.FileName = file_name
      opts.[File Name] = file_path
      opts.Type = "Automatic"
      opts.[File based] = "Automatic"
      opts.Sparse = "Automatic"
      opts.[Column Major] = "Automatic"
      prob_mtxs = prob_mtxs + {opts}

      file_name = "utilities_" + prefix + "_" + market + ".MTX"
      file_path = output_dir + "/" + file_name
      opts = null
      opts.Label = prefix + "_" + market + " Utility"
      opts.Compression = 1
      opts.FileName = file_name
      opts.[File Name] = file_path
      opts.Type = "Automatic"
      opts.[File based] = "Automatic"
      opts.Sparse = "Automatic"
      opts.[Column Major] = "Automatic"
      util_mtxs = util_mtxs + {opts}

      file_name = "logsums_" + prefix + "_" + market + ".MTX"
      file_path = output_dir + "/" + file_name
      opts = null
      opts.Label = prefix + "_" + market + " Logsum"
      opts.Compression = 1
      opts.FileName = file_name
      opts.[File Name] = file_path
      opts.Type = "Automatic"
      opts.[File based] = "Automatic"
      opts.Sparse = "Automatic"
      opts.[Column Major] = "Automatic"
      logsum_mtxs = logsum_mtxs + {opts}
    end

    nle_opts.Output.[Probability Matrices] = prob_mtxs
    nle_opts.Output.[Utility Matrices] = util_mtxs
    nle_opts.Output.[Logsum Matrices] = logsum_mtxs

    // Run model
    ret_value = RunMacro("TCB Run Procedure", "NestedLogitEngine", nle_opts, &Ret)

    // Make sure output matrices match skim matrix dimensions
    if tables.zone_tbl.set_name <> null then do
      skim_file = matrices[1][2].file
      // for each market segment
      for i = 1 to nle_opts.Output.[Probability Matrices].length do
        trip_path = nle_opts.Output.[Probability Matrices][i].[File Name]
        RunMacro("Expand Matrix to All Centroids", trip_path, skim_file)
      end
    end
  end

  if combine_outputs then RunMacro("GT - Combine MC Matrices", MacroOpts)

  RunMacro("Close All")
EndMacro

/*
The NLM model will create three matrices for each combination of period,
purpose, and segment. This macro combines all of them into period matrices.
This macro is called by "GT - Mode Choice NLM" if the "combine_outputs" option
is true.

Inputs
  MacroOpts
    output_dir
    param_file
    period

  All three inputs are identical to those needed by "GT - Mode Choice NLM"
*/

Macro "GT - Combine MC Matrices" (MacroOpts)

  output_dir = MacroOpts.output_dir
  param_file = MacroOpts.param_file
  period = MacroOpts.period

  // Use the parameter file to get the unique values of period, purpose, and
  // segment.
  df = CreateObject("df")
  df.read_csv(param_file)
  df.filter("Period = '" + period + "'")
  a_types = {"probabilities", "logsums", "utilities"}
  v_purposes = df.unique(df.tbl.Purpose)
  v_segments = df.unique(df.tbl.Segment)

  to_mtx_file = output_dir + "/_" + period + "_mc_share_results.mtx"
  if GetFileInfo(to_mtx_file) <> null then DeleteFile(to_mtx_file)

  // Loop over each purpose, segment, and matrix
  for type in a_types do
    for purpose in v_purposes do
      for segment in v_segments do
        from_mtx_file = output_dir + "/" + type + "_" + period + "_" +
          purpose + "_" + segment + ".mtx"

        a_to_delete = a_to_delete + {from_mtx_file}
        from_mtx = OpenMatrix(from_mtx_file, )
        a_core_names = GetMatrixCoreNames(from_mtx)
        v_core_names = type + " " + purpose + " " + segment + " " + A2V(a_core_names)
        a_final_core_names = a_final_core_names + V2A(v_core_names)
        a_temp = CreateMatrixCurrencies(from_mtx, , , )
        for a = 1 to a_temp.length do
          a_from_curs = a_from_curs + {a_temp[a][2]}
        end
      end
    end
  end

  // Combine all matrix currencies into a single matrix
  opts = null
  opts.[File Name] = to_mtx_file
  opts.Label = period + " mc share results"
  CombineMatrices(a_from_curs, opts)
  a_from_curs = null

  // Rename cores
  to_mtx = OpenMatrix(to_mtx_file, )
  SetMatrixCoreNames(to_mtx, a_final_core_names)
  a_final_core_names = null


  // Delete all the individual matrices
  from_mtx = null
  a_temp = null
  for file in a_to_delete do
    DeleteFile(file)
  end
EndMacro

/*
Extracts the data sources for each alternative on the "Utilies" tab of the Logit
Model Application GUI (for all segments).

For example, a variable in the utility equation might be
"drive_time" and an alternative named "DAToll" might use the matrix core
"hwy_skim.SOV_toll_time" to get the right value. In that case, the output
CSV would have a row like so:

segment  | alternative  | coefficient | source_name
--------------------------------------------------------------
inc1     | DAToll       | drive_time  | hwy_skim.SOV_toll_time

For complex models, the MDL file can be difficult to check for errors. This
puts it in a format more conducive to error checking.

It also serves to document some obscure methods of the NLM.Model.
*/

Macro "GT - Get Utility Variables" (mdl_file)

  // Create model object.
  model = null
  model = CreateObject("NLM.Model")
  model.Read(mdl_file, 1)

  // For each segment
  for s = 1 to model.GetSegmentCount() do
    seg = model.GetSegment(s)

    // For each alternative
    for a = 1 to seg.GetAlternativeCount() do
      alt = seg.GetAlternative(a)
      if alt.Access.Items <> null then do
        access = alt.Access
        // For each item in the data access list
        for d = 1 to access.Count() do
          fda = access.Get(d)

          variable_name = fda.Name
          core_or_field_name = fda.Access.Source.Name + "." + fda.Access.Name

          csv.segment = csv.segment + {seg.Name}
          csv.alternative = csv.alternative + {alt.Name}
          csv.variable = csv.variable + {variable_name}
          csv.value = csv.value + {core_or_field_name}
          csv.description = csv.description + {""}
        end
      end
    end
  end

  // Create a data frame and write to CSV
  df = CreateObject("df", csv)
  {drive, directory, name, ext} = SplitPath(mdl_file)
  csv_file = drive + directory + name + ".csv"
  df.write_csv(csv_file)
EndMacro

/*
Sets the data sources for each alternative on the "Utilies" tab of the Logit
Model Application GUI (for all segments). For example, it might tell the drive-
alone alternative which skim core to use for drive time.

Inputs
  csv_file
    String
    Path to CSV file with the same format produced by "GT - Get Utility
    Variables."

  mdl_file
    String
    Path to .mdl file that will have its variables set.
*/

Macro "GT - Set Utility Variables" (csv_file, mdl_file)

  // Clear out any current utility variables
  RunMacro("GT - Clear Utility Variables", mdl_file)

  // Create a df object just to access some of its methods
  df = CreateObject("df")

  // Read the csv parameter file
  params = RunMacro("Read Parameter File", csv_file)

  // Create model object.
  model = null
  model = CreateObject("NLM.Model")
  model.Read(mdl_file, 1)

  // Collect an array of existing variables in the model. They are called
  // "fields" in the NLM.Model.
  for f = 1 to model.Fields.Items.length do
    existing_fields = existing_fields + {model.Fields.Items[f][1]}
  end

  // For each segment
  for s = 1 to params.length do
    segment = params[s][1]

    seg_params = params.(segment)
    seg = model.GetSegment(segment)

    // Collect an array of existing terms. Each segment can have different terms.
    existing_terms = null
    for t = 1 to seg.Terms.Items.length do
      existing_terms = existing_terms + {seg.Terms.Items[t][1]}
    end

    // For each alternative
    for a = 1 to seg_params.length do
      alternative = seg_params[a][1]

      alt_params = seg_params.(alternative)
      alt = seg.GetAlternative(alternative)

      // For each variable
      for v = 1 to alt_params.length do
        variable = alt_params[v][1]

        source = alt_params.(variable)
        {label, field_or_core} = ParseString(source, ".")

        // Create a model field if it doesn't already exist
        if !df.in(variable, existing_fields) then do
          fld = model.CreateField(variable, )
          existing_fields = existing_fields + {variable}
        end
        // Create a segment term if it doesn't already exist
        if !df.in(variable, existing_terms) then do
          term = seg.CreateTerm(variable, 0, ) // term name and coefficient
          existing_terms = existing_terms + {variable}
        end

        fld = model.GetField(variable)
        da = model.CreateDataAccess("data", label, field_or_core)
        alt.SetAccess(fld, da, )
      end
    end
  end

  // write out the new mdl file for manual review
  model.Write(mdl_file)
  model.Clear()
EndMacro

/*
Clears out any values on the "Utilities" tab of the Logit Model Application GUI.
Clears values for all segments.
*/

Macro "GT - Clear Utility Variables" (mdl_file)

  // Create model object.
  model = null
  model = CreateObject("NLM.Model")
  model.Read(mdl_file, 1)

  // For each segment
  for s = 1 to model.GetSegmentCount() do
    seg = model.GetSegment(s)

    // For each alternative
    for a = 1 to seg.GetAlternativeCount() do
      alt = seg.GetAlternative(a)

      if alt.Access.Items <> null then do

        access = alt.Access
        // For each item in the data access list
        for name in access.GetNames() do
          fld = model.GetField(name)
          alt.SetAccess(fld, "", )
        end
      end
    end
  end

  // write out the new mdl file for manual review
  model.Write(mdl_file)
  model.Clear()
EndMacro
