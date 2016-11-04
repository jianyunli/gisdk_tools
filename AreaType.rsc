/*
Collection of tools often used related to area type

1. Density Calculation and AT Classification
2. Smoothing Area Type Boundaries
3. Tagging Highway Network

Inputs:
MacroOpts             Options array with the following fields
  MacroOpts.tazDBD      File    TAZ file name
  MacroOpts.seBIN       File    SE BIN file name
  MacroOpts.areaField   String  Name of area field in TAZ layer
  MacroOpts.hhField     String  Name of household field in TAZ layer
  MacroOpts.empField    String  Name of employment field in TAZ layer
  MacroOpts.types       Array   e.g. {"Rural", "Suburban", "Urban"}
  MacroOpts.thresholds  Array   Density thresholds (e.g. {0, 211, 950})
  * Types and thresholds must both be sorted by increasing density.
  MacroOpts.hwyDBD      File    Highway file name

Outputs:
Modifies the TAZ layer by adding two fields with data:
  "Density"
  "AreaType"
  "ATSmoothed"
Modifies the Highway layer by adding one field with data:
  "AreaType"
*/

Macro "Area Type" (MacroOpts)

  // Test Inclusion - this macro uses SelectByVicinity()
  // If the script changes the user's settings, change it back at end of macro
  inclusionChanged = "No"
  if GetSelectInclusion() = "Intersecting" then do
      SetSelectInclusion("Enclosed")
      inclusionChanged = "Yes"
  end

  RunMacro("Calculate Area Type", MacroOpts)
  RunMacro("Smooth Area Type", MacroOpts)
  RunMacro("Tag Highway with Area Type", MacroOpts)

  if inclusionChanged = "Yes" then do
      SetSelectInclusion("Intersecting")
  end
EndMacro

/*
Calculates and classifies area types based on density.  Density is calculated
with the following formula:

Density = (Households + Employment ) / Area

*/

Macro "Calculate Area Type" (MacroOpts)

  tazDBD = MacroOpts.tazDBD
  seBIN = MacroOpts.seBIN
  areaField = MacroOpts.areaField
  hhField = MacroOpts.hhField
  empField = MacroOpts.empField
  types = MacroOpts.types
  thresholds = MacroOpts.thresholds

  // Open the TAZ layer
  {tLyr} = GetDBLayers(tazDBD)
  tLyr = AddLayerToWorkspace(tLyr, tazDBD, tLyr)

  // Open the SE bin file and add fields
  seTbl = OpenTable("se", "FFB", {seBIN})
  a_fields = {
    {"Density", "Real", 10, 3,,,,"Used to calculate initial AT"},
    {"AreaType", "Character", 10,,,,,"Area type of the zone" }
  }
  RunMacro("TCB Add View Fields", {seTbl, a_fields})

  // Join the se table to the TAZ dbd
  jv = JoinViews("jv", tLyr + ".TAZ", seTbl + ".ID", )

  // Get Column Vectors
  v_area = GetDataVector(jv + "|", tLyr + "." + areaField, )
  v_hh = GetDataVector(jv + "|", seTbl + "." + hhField, )
  v_totemp = GetDataVector(jv + "|", seTbl + "." + empField, )

  // Compute density
  v_dens = (v_hh + v_totemp ) / v_area

  // Loop over the area types and assign based on density thresholds
  v_atype = Vector(v_dens.length, "String", )
  for t = 1 to types.length do
    v_atype = if (v_dens >= thresholds[t])
    then types[t]
    else v_atype
  end

  SetDataVector(jv + "|", seTbl + "." + "Density", v_dens, )
  SetDataVector(jv + "|", seTbl + "." + "AreaType", v_atype, )

  CloseView(jv)
  CloseView(seTbl)
  DropLayerFromWorkspace(tLyr)

EndMacro

/*
Uses buffers to smooth the boundaries between the different area types.
*/

Macro "Smooth Area Type" (MacroOpts)

  tazDBD = MacroOpts.tazDBD
  seBIN = MacroOpts.seBIN
  types = MacroOpts.types

  // Create map of TAZs we se data joined
  map = RunMacro("G30 new map", tazDBD)
  {tLyr} = GetDBLayers(tazDBD)

  // Join the se table to the TAZ layer
  // Add a "ATSmoothed" field to track which TAZs have been smoothed
  // to avoid smoothing them more than once.
  seTbl = OpenTable("se", "FFB", {seBIN})
  a_fields = {
    {"ATSmoothed", "Integer", 10,,,,,
    "Whether or not the area type was smoothed"}
  }
  RunMacro("TCB Add View Fields", {seTbl, a_fields})
  jv = JoinViews("jv", tLyr + ".TAZ", seTbl + ".ID", )


  // Loop over the area types in reverse order (e.g. Urban to Rural)
  // Skip the last (least dense) area type (usually "Rural") as those do
  // not require buffering.
  for t = types.length to 2 step -1 do
    type = types[t]

    // Select TAZs of current type
    query = "Select * where AreaType = '" + type + "'"
    n = SelectByQuery("selection", "Several", query)

    if n > 0 then do
      // Create a temporary 1-mile buffer (deleted at end of macro)
      // and add to map.
      a_path = SplitPath(tazDBD)
      bufferDBD = a_path[1] + a_path[2] + "ATbuffer.dbd"
      CreateBuffers(bufferDBD, "buffer", {"selection"}, "Value", {1},)
      bLyr = AddLayer(map,"buffer",bufferDBD,"buffer")

      // Select zones within the 1 mile buffer that have not already
      // been smoothed.
      SetLayer(tLyr)
      n2 = SelectByVicinity("in_buffer", "several", "buffer|", , )
      qry = "Select * where ATSmoothed = 1"
      n2 = SelectByQuery("in_buffer", "Less", qry)

      if n2 > 0 then do
        // Set those zones' area type to the current type and mark
        // them as smoothed
        opts = null
        opts.Constant = type
        v_atype = Vector(n2, "String", opts)
        opts = null
        opts.Constant = 1
        v_smoothed = Vector(n2, "Long", opts)
        SetDataVector(
          jv + "|in_buffer", seTbl + "." + "AreaType", v_atype,
        )
        SetDataVector(
          jv + "|in_buffer", seTbl + "." + "ATSmoothed", v_smoothed,
        )
      end

      DropLayer(map, bLyr)
      DeleteDatabase(bufferDBD)
    end
  end

  CloseView(jv)
  CloseView(seTbl)
  CloseMap(map)
EndMacro

/*
Tags highway links with the area type of the TAZ they are nearest to.
*/

Macro "Tag Highway with Area Type" (MacroOpts)

  tazDBD = MacroOpts.tazDBD
  seBIN = MacroOpts.seBIN
  hwyDBD = MacroOpts.hwyDBD
  types = MacroOpts.types

  // Create map of TAZs and join se data
  map = RunMacro("G30 new map", tazDBD)
  {tLyr} = GetDBLayers(tazDBD)
  seTbl = OpenTable("se", "FFB", {seBIN})
  jv = JoinViews("jv", tLyr + ".TAZ", seTbl + ".ID", )

  // Add highway links to map
  hwyDBD = hwyDBD
  {nLayer, lLyr} = GetDBLayers(hwyDBD)
  lLyr = AddLayer(map, lLyr, hwyDBD, lLyr)

  // Add the AreaType field to the network
  a_fields = {{"AreaType", "Character", 10, }}
  ret = RunMacro("TCB Add View Fields", {lLyr, a_fields})
  // Loop over each area type starting with most dense.  Skip the first.
  // All remaining links after this loop will be tagged with the lowest
  // area type.
  for t = types.length to 2 step -1 do
    type = types[t]

    // Select TAZs of current type
    SetView(jv)
    query = "Select * where AreaType = '" + type + "'"
    n = SelectByQuery("selection", "Several", query)

    if n > 0 then do
      // Create buffer and add it to the map
      buffer_dbd = GetTempFileName(".dbd")
      opts = null
      opts.Exterior = "Merged"
      opts.Interior = "Merged"
      CreateBuffers(buffer_dbd, "buffer", {"selection"}, "Value", {100/5280}, )
      bLyr = AddLayer(map, "buffer", buffer_dbd, "buffer")

      // Select links within the buffer that haven't been updated already
      SetLayer(lLyr)
      n2 = SelectByVicinity(
        "links", "several", tLyr + "|selection", 0, )
      query = "Select * where AreaType <> null"
      n2 = SelectByQuery("links", "Less", query)

      // Remove buffer from map
      DropLayer(map, bLyr)

      if n2 > 0 then do
        // For these links, update their area type and mark them as updated
        v_at = Vector(n2, "String", {{"Constant", type}})
        SetDataVector(lLyr + "|links", "AreaType", v_at, )
      end
    end
  end

  // Select all remaining links and assign them to the
  // first (lowest density) area type.
  SetLayer(lLyr)
  query = "Select * where AreaType = null"
  n = SelectByQuery("links", "Several", query)
  if n > 0 then do
      v_at = Vector(n, "String", {{"Constant", types[1]}})
      SetDataVector(lLyr + "|links", "AreaType", v_at, )
  end

  CloseMap(map)
EndMacro
