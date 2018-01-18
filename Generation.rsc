/*
Takes aggregate zonal stats (e.g. average household size) and creates
distributions of households by (e.g. 1-person, 2-person, etc).

Input:
MacroOpts
  Options Array
  Containing all arguments needed

  se_bin
    String
    Full path to the scenario se BIN file

  hh_field
    String
    Field name in se_bin containing households.

  mtables
    Opts Array
    Links a field from the SE table to it's marginal table.
    For example:
    mtables.avg_size = dir + "/disagg_hh_size.csv"
    This joins the hh_size.csv marginal table using the "avg_size" field in the
    taz layer. The marginal csv tables should look like the following:

    avg     siz1    siz2
    1.0     1       0
    1.1     .98     .02
    etc

    The first column can have any name. The remaining columns must match the
    joint/seed table. In the example above, the joint/seed table must have a
    column named "siz" with values of 1 and 2 in it.

Output:
Appends marginal distributions to the se table

Depends:
ModelUtilities.rsc  "Perma Join"
                    "Remove Field"
*/

Macro "HH Marginal Creation" (MacroOpts)

  // Argument extraction
  se_bin = MacroOpts.se_bin
  hh_field = MacroOpts.hh_field
  mtables = MacroOpts.mtables

  // Check that the necessary fields are present in the se table
  for t = 1 to mtables.length do
    a_reqFields = a_reqFields + {mtables[t][1]}
  end
  se_tbl = OpenTable("se", "FFB", {se_bin})
  a_fields = GetFields(se_tbl, "All")
  a_fields = a_fields[1]
  string = "The following fields are missing from 'se_bin': "
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
  for m = 1 to mtables.length do
    master_index = mtables[m][1]
    tblFile = mtables.(master_index)

    // Open mtable and get marginal category names.  Also get the max/min
    // avg values included in the table.
    tbl = OpenTable("tbl", "CSV", {tblFile})
    a_fieldnames = GetFields(tbl, "All")
    a_fieldnames = a_fieldnames[1]
    slave_index = a_fieldnames[1]
    a_catnames = ExcludeArrayElements(a_fieldnames, 1, 1)
    v_idx = GetDataVector(tbl + "|", slave_index, )
    big = ArrayMax(V2A(v_idx))
    small = ArrayMin(V2A(v_idx))
    CloseView(tbl)

    // Before joining, delete any category fields that might exist
    // from a previous run.
    se_tbl = OpenTable("se", "FFB", {se_bin})
    RunMacro("Remove Field", se_tbl, a_catnames)

    // Make sure there are no null values in the master index field and cap them
    // to the values of 'big' and 'small'. Also, get a vector of total
    // households.
    v = nz(GetDataVector(se_tbl + "|", master_index, ))
    v = min(big, v)
    v = max(small, v)
    SetDataVector(se_tbl + "|", master_index, v, )
    v_hh = nz(GetDataVector(se_tbl + "|", hh_field, ))
    CloseView(se_tbl)
    RunMacro("Perma Join", se_bin, master_index, tblFile, slave_index)
    se_tbl = OpenTable("se", "FFB", {se_bin})

    // Convert the category fields in the se table from percents
    // to households by multiplying by the household field.
    for c = 1 to a_catnames.length do
      catname = a_catnames[c]

      v_pct = GetDataVector(se_tbl + "|", catname, )
      v_hhs = v_pct * v_hh
      SetDataVector(se_tbl + "|", catname, v_hhs, )
    end

    CloseView(se_tbl)
  end

EndMacro


/*
With marginals created in the se table, use R to create the joint distribution
for each TAZ.

Input:
  MacroOpts
    Named array that stores all macro arguments

    rscriptexe
      String
      Path to the Rscript.exe file

    rscript
      String
      Path to the Generation.R script to excute

    se_bin
      String
      Path to the zonal/se bin file

    taz_field
      Optional string
      Name of the field containing TAZ IDs. Defaults to "ID".

    internal_query
      Optional string
      GISDK query that identifies which zones are internal. By default, the
      query is assumed to be "InternalZone = 'Internal'".

    seed_tbl
      String
      Path to seed table (csv)

    output_dir
      String
      Path to the output folder where the output (HHDisaggregation.csv) will be
      saved.

Returns:
  Writes out HHDisaggregation.csv.
*/
Macro "HH Joint Distribution" (MacroOpts)

  // Argument extraction
  rscriptexe = MacroOpts.rscriptexe
  rscript = MacroOpts.rscript
  se_bin = MacroOpts.se_bin
  taz_field = MacroOpts.taz_field
  internal_query = MacroOpts.internal_query
  seed_tbl = MacroOpts.seed_tbl
  output_dir = MacroOpts.output_dir

  if taz_field = null then taz_field = "ID"

  // The R script requires a field named "InternalZone" with values of
  // "Internal" identifying internal zones (where disagg is applied). Create
  // that field if needed.
  if internal_query <> null  then do
    view = OpenTable("view", "FFB", {se_bin})
    internal_query = RunMacro("Normalize Query", internal_query)
    if internal_query <> "Select * where InternalZone = 'Internal'" then do
      a_fields = {
        {
          "InternalZone", "Character", 10, 0, , , ,
          "Identifies internal zones|Created by disagg model"
        }
      }
      RunMacro("Add Fields", view, a_fields, )
      SetView(view)
      n = SelectByQuery("temp", "several", internal_query)
      if n = 0
        then Throw("query: '" + query + "' returned no internal zones")
        else do
          opts = null
          opts.Constant = "Internal"
          v = Vector(n, "String", opts)
          SetDataVector(view + "|temp", "InternalZone", v, )
        end
      CloseView(view)
    end
  end

  // Delete R output if it exists
  rCSV = output_dir + "/HHDisaggregation.csv"
  rDCC = Substitute(rCSV, ".csv", ".DCC",)
  if GetFileInfo(rCSV) <> null then DeleteFile(rCSV)
  if GetFileInfo(rDCC) <> null then DeleteFile(rDCC)

  // Prepare arguments for "Run R Script"
  rscriptexe = rscriptexe
  rscript = rscript
  OtherArgs = {se_bin, taz_field, seed_tbl, output_dir}
  RunMacro("Run R Script", rscriptexe, rscript, OtherArgs)
EndMacro


/*
Creates trip productions by purpose for residents.

MacroOpts
Options array containing all arguments to the function

  MacroOpts.param_work
    String
    Path to CSV containing the work rates

  MacroOpts.param_nonwork
    String
    Path to CSV containing the non-work rates

  MacroOpts.disagg_file
    String
    Path to a disaggregated household table (usually the output
    of the "HH Joint Distribution" macro). This table must be in
    long form. Example:

    geo_taz|siz|inc|weight
    1      |  1|  H|     2
    1      |  1|  L|     3
    etc.

    Column names must match to those specified in the work and non- work
    paramter files (e.g. "siz" and "inc"). The macro will automatically match
    them.

  MacroOpts.return_dfs
    True/False
    If true, the work and nonwork tables are returned as dataframes. If false,
    the default, the tables are written to bin files in the same directory
    as the disagg_file.

  Returns
    Depends on return_dfs option
*/

Macro "Cross-Classification Method" (MacroOpts)

  disagg_file = MacroOpts.disagg_file
  return_dfs = MacroOpts.return_dfs

  // Argument check
  if disagg_file = null then Throw("'disagg_file' not provided")

  // Set output directory to location of disagg file
  {drive, directory, filename, ext} = SplitPath(disagg_file)
  output_dir = RunMacro("Normalize Path", drive + directory)

  // Open the disagg tbl
  disagg_tbl = OpenTable("disag", "CSV", {disagg_file, })

  a_type = {"work", "nonwork"}
  for t = 1 to a_type.length do
    type = a_type[t]

    // Open the trip rate table and determine marginal names
    // The assumed format of the rate table is that the last 2 columns
    // will be "purpose" and "rate".  Every other field is assumed to be a
    // marginal field.
    rate_file = MacroOpts.("param_" + type)
    rate_tbl = OpenTable("rates", "CSV", {rate_file})
    a_fields = GetFields(rate_tbl, "All")
    a_fields = a_fields[1]
    pos = ArrayPosition(a_fields, {"purpose"}, )
    a_margnames = ExcludeArrayElements(a_fields, pos, 2)

    // Join the rate table to the disagg output
    a_master_specs = null
    a_slave_specs = null
    for m = 1 to a_margnames.length do
      margname = a_margnames[m]

      a_master_specs = a_master_specs + {disagg_tbl + "." + margname}
      a_slave_specs = a_slave_specs + {rate_tbl + "." + margname}
    end
    opts = null
    opts.O = "O" // specifies multiple slave fields per master field
    jv = JoinViewsMulti("jv", a_master_specs, a_slave_specs, opts)

    df = CreateObject("df")
    opts = null
    opts.view = jv
    df.read_view(opts)
    df.mutate("trips", df.tbl.weight * df.tbl.rate)

    if return_dfs
      then result = result + {df}
      else do
        df.write_bin(output_dir + "/" + type + "_trips.bin")
      end

    CloseView(jv)
    CloseView(rate_tbl)
  end

  CloseView(disagg_tbl)
  if return_dfs then return(result)
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
