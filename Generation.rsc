/*
Takes aggregate zonal stats like total population and vehicles and creates
distributions of households by individual sizes, number of vehicles, and
number of workers.

Input:
MacroOpts
  Options Array
  Containing all arguments needed

  MacroOpts.se_bin
    String
    Full path to the scenario se BIN file

  MacroOpts.hhField
    String
    Field name in the taz layer that has households

  MacroOpts.mtables
    Opts Array
    Links a field from the SE table to it's marginal table.
    For example:
    mtables.HHPopulation = dir + "/disagg_hh_size.csv"
    This links the hh_size.csv marginal table to the
    "HHPopulation" field in the taz layer.


Output:
Appends marginal distributions to the se table

Depends:
ModelUtilities.rsc  "Perma Join"
                    "Remove Field"
*/

Macro "HH Marginal Creation" (MacroOpts)

  // Check that the necessary fields are present in the se table
  a_reqFields = {MacroOpts.hhField}
  for t = 1 to MacroOpts.mtables.length do
    a_reqFields = a_reqFields + {MacroOpts.mtables[t][1]}
  end

  se_tbl = OpenTable("se", "FFB", {MacroOpts.se_bin})
  a_fields = GetFields(se_tbl, "All")
  a_fields = a_fields[1]
  string = "The following fields are missing: "
  missing = "False"
  for i = 1 to a_reqFields.length do
    reqField = a_reqFields[i]

    opts = null
    opts.[Case Sensitive] = "True"
    if ArrayPosition(a_fields, {reqField}, opts) = 0 then do
      missing = "True"
      string = string + "'" + reqField + "' "
    end
  end
  if missing then do
    Throw(string)
  end

  CloseView(se_tbl)

  // for each marginal table
  for m = 1 to MacroOpts.mtables.length do
    margName = MacroOpts.mtables[m][1]
    tblFile = MacroOpts.mtables.(margName)

    // Open table and get marginal category names.  Also get the max/min
    // avg values included in the table.
    tbl = OpenTable("tbl", "CSV", {tblFile})
    a_fieldnames = GetFields(tbl, "All")
    a_fieldnames = a_fieldnames[1]
    a_catnames = ExcludeArrayElements(a_fieldnames, 1, 1)
    v_avg = GetDataVector(tbl + "|", "avg", )
    big = ArrayMax(V2A(v_avg))
    small = ArrayMin(V2A(v_avg))
    CloseView(tbl)

    // Before joining, delete any category fields that might exist
    // from a previous run.
    se_tbl = OpenTable("se", "FFB", {MacroOpts.se_bin})
    RunMacro("Remove Field", se_tbl, a_catnames)

    // Calculate an average field in order to join the marginal table
    // For example, if the current marginal is workers, calculate
    // an average workers / household for each zone.  Also, cap the calculated
    // average to the max/min included in the disagg table.
    v_hh = GetDataVector(se_tbl + "|", MacroOpts.hhField, )
    v_marg = GetDataVector(se_tbl + "|", margName, )
    v_mavg = round(v_marg / v_hh, 2)
    v_mavg = if (v_mavg = null) then 0 else v_mavg
    v_mavg = min(v_mavg, big)
    v_mavg = max(v_mavg, small)
    a_fields = {{"mavg", "Real", 10, 2}}
    RunMacro("TCB Add View Fields", {se_tbl, a_fields})
    SetDataVector(se_tbl + "|", "mavg", v_mavg, )


    CloseView(se_tbl)
    RunMacro("Perma Join", MacroOpts.se_bin, "mavg", tblFile, "avg")
    se_tbl = OpenTable("se", "FFB", {MacroOpts.se_bin})
    RunMacro("Remove Field", se_tbl, "mavg")
    RunMacro("Remove Field", se_tbl, "avg")

    // Convert the category fields in the se table from percents
    // to households by multiplying by the household field.
    for c = 1 to a_catnames.length do
      catname = a_catnames[c]

      v_pct = GetDataVector(se_tbl + "|", catname, )
      v_hhs = v_pct * v_hh
      SetDataVector(se_tbl + "|", catname, v_hhs, )
    end
  end

  CloseView(se_tbl)
EndMacro


/*
With marginals created in the se table, use R to create the joint distribution
for each TAZ.

Input:
MacroOpts
  MacroOpts.rscriptexe
  MacroOpts.rscript
  MacroOpts.se_bin
  MacroOpts.Seed
  MacroOpts.output_dir
*/
Macro "HH Joint Distribution" (MacroOpts)

  // Delete R output if it exists
  rCSV = MacroOpts.output_dir + "/HHDisaggregation.csv"
  rDCC = Substitute(rCSV, ".csv", ".DCC",)
  if GetFileInfo(rCSV) <> null then DeleteFile(rCSV)
  if GetFileInfo(rDCC) <> null then DeleteFile(rDCC)

  // Prepare arguments for "Run R Script"
  rscriptexe = MacroOpts.rscriptexe
  rscript = MacroOpts.rscript
  se_bin = MacroOpts.se_bin
  seedTbl = MacroOpts.Seed
  output_dir = MacroOpts.output_dir
  OtherArgs = {se_bin, seedTbl, output_dir}
  RunMacro("Run R Script", rscriptexe, rscript, OtherArgs)
EndMacro


/*
Creates trip productions by purpose for residents.

MacroOpts
Options array containing all arguments to the function

  MacroOpts.se_bin
    String
    Path to se bin file

  MacroOpts.param_work
    String
    Path to CSV containing the work rates

  MacroOpts.param_nonwork
    String
    Path to CSV containing the non-work rates

  MacroOpts.output_dir
    String
    Path to output folder where temporary files are placed
*/

Macro "Cross-Classification Method" (MacroOpts)

  a_type = {"work", "nonwork"}
  for t = 1 to a_type.length do
    type = a_type[t]

    // Open the trip rate table and determine marginal names
    // The assumed format of the rate table is that the last 2 columns
    // will be "purpose" and "rate".  Every other field is assumed to be a
    // marginal field.
    rateFile = MacroOpts.("param_" + type)
    rateTbl = OpenTable("rates", "CSV", {rateFile})
    a_fields = GetFields(rateTbl, "All")
    a_fields = a_fields[1]
    pos = ArrayPosition(a_fields, {"purpose"}, )
    a_margnames = ExcludeArrayElements(a_fields, pos, 2)

    // Open the disagg output.  The file named is assumed to be in the format
    // of "marg1_by_marg2.csv" or "marg1_by_marg2_by_marg3.csv" if 3D.
    // The order of the marginals listed in the name must match the column
    // order in the rate table.
    for m = 1 to a_margnames.length do
      margname = a_margnames[m]

      if m = 1 then fileName = margname else
      fileName = fileName + "_by_" + margname
    end
    fileName = fileName + ".csv"

    disagTbl = OpenTable(
      "disag", "CSV",
      {MacroOpts.output_dir + "/" + fileName}
    )

    // Join the rate table to the disagg output
    a_master_specs = null
    a_slave_specs = null
    for m = 1 to a_margnames.length do
      margname = a_margnames[m]

      a_master_specs = a_master_specs + {disagTbl + "." + margname}
      a_slave_specs = a_slave_specs + {rateTbl + "." + margname}
    end
    opts = null
    opts.O = "O" // specifies multiple slave fields per master field
    jv = JoinViewsMulti("jv", a_master_specs, a_slave_specs, opts)
    SetView(jv)

    // Use the gplyr library to make the rest easier
    df = CreateObject("df")
    opts = null
    opts.view = jv
    df.read_view(opts)
    // Select only the fields of interest
    df.select({"ID", "purpose", "rate", "HH"})
    // Calculate trips
    df.mutate("trips", df.tbl.HH * df.tbl.rate)
    // Summarize the table by TAZ ID and purpose
    df.group_by({"ID", "purpose"})
    agg = null
    agg.trips = {"sum"}
    df.summarize(agg)
    // Remove count field
    df.remove("Count")
    // Spread the table
    df.spread("purpose", "sum_trips", 0)
    // Write table to CSV and join to se table
    outputFile = MacroOpts.output_dir + "/trips.csv"
    df.write_csv(outputFile)
    RunMacro("Perma Join",
      MacroOpts.se_bin, "ID",
      outputFile, "ID"
    )

    // Add descriptions to the fields added to the se table
    rateTbl = OpenTable("rates", "CSV", {rateFile})
    v_purp = GetDataVector(rateTbl + "|", "purpose", )
    opts = null
    opts.Unique = "True"
    v_purp = SortVector(v_purp, opts)
    a_info = GetFileInfo(rateFile)
    rateTblShort = a_info[1]
    field = null
    description = null
    for p = 1 to v_purp.length do
      field = field + {v_purp[p]}
      description = description + {
        "Generation|" +
        "Productions|" +
        "See " + rateTblShort + " for more info"
      }
    end
    RunMacro("Add Field Description", MacroOpts.se_bin, field, description)

    RunMacro("Close All")
    DeleteFile(outputFile)
  end
EndMacro

/*
Balance
Balances production and attraction fields based on a parameter table.

MacroOpts
  Options array containing all arguments to the function

  MacroOpts.tbl
    String
    Path to table file with production and attraction columns

  MacroOpts.balance_tbl
    String
    Path to balance table.  This table has the following fields
      prod_field
      attr_field
      balance
      description
    Each row describes two fields that should be balanced, and states
    whether to balance "to productions", "to attractions", or to apply the
    "nhb" treatment (balance to prod and then set prod to attr).

Returns
  Two vectors
    out_p
      Each production field

    out_a
      Each attraction field

    out_f
      The balance factor applied
*/

Macro "Balance" (MacroOpts)

  // Open the balance table and se bin file
  bal_tbl = OpenTable("balance", "CSV", {MacroOpts.balance_tbl})
  se = OpenTable("se", "FFB", {MacroOpts.tbl})

  // Get the column vectors needed
  v_pfield = GetDataVector(bal_tbl + "|", "prod_field", )
  v_afield = GetDataVector(bal_tbl + "|", "attr_field", )
  v_bal = GetDataVector(bal_tbl + "|", "balance", )

  // Loop over each row of the table
  for i = 1 to v_pfield.length do
    pfield = v_pfield[i]
    afield = v_afield[i]
    bal = v_bal[i]

    // Get production / attraction vectors
    v_p = GetDataVector(se + "|", pfield, )
    v_a = GetDataVector(se + "|", afield, )
    total_p = VectorStatistic(v_p, "sum", )
    total_a = VectorStatistic(v_a, "sum", )

    // Store unbalanced Ps and As in a table to be written out
    unbalanced.(pfield) = v_p
    unbalanced.(afield) = v_a

    // Balance
    if bal = "to productions" then do
      factor = total_p / total_a
      v_a = v_a * factor
    end
    else if bal = "to attractions" then do
      factor = total_a / total_p
      v_p = v_p * factor
    end
    else if bal = "nhb" then do
      factor = total_p / total_a
      v_a = v_a * factor
      v_p = v_a
    end

    // Set vectors
    SetDataVector(se + "|", pfield, v_p, )
    SetDataVector(se + "|", afield, v_a, )

    // Fill output arrays
    out_p = out_p + {pfield}
    out_a = out_a + {afield}
    out_f = out_f + {factor}
  end

  // Convert output arrays to vectors and return a named array
  tbl = null
  tbl.p = A2V(out_p)
  tbl.a = A2V(out_a)
  tbl.factor = A2V(out_f)

  return({tbl, unbalanced})

EndMacro
