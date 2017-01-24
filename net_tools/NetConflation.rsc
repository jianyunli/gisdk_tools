/*
Code Incomplete

This is an attemp to improve on the LinkJoin macro. That macro was
designed to compare networks that were very similar - usually scenario
networks created from the same master network. In those networks, most
links are identical, and the ones that aren't are compared using
endpoint/shapepoint proximity. In networks that are very different, say an old
model network and a navteq layer, LinkJoin() breaks down.

This approach will chop both networks up into small links and then compare
measures like proximity, azimuth/heading, and curvature to select the
most likely link. Like LinkJoin(), these measures will be used to create
a confidence metric.

(eventual) Inputs:
  target_dbd
    String
    Full path to the target dbd. This is the layer you want to be tagged.

  source_dbd
    String
    Full path to the source dbd. This dbd contains the link IDs you want
    placed on the target dbd.

do not include a selection set here. If only wanting to perform on a set
of the target links, export a dbd of the set before calling this macro

Helpful GISDK macros:
  SelectNearestFeatures()
  CoordToLineDistance()
  LocateNearestRecord()
  LocateNearestRecords()
  CoordToLineDistance()
  RunMacro("get midpoint along line", link_id)
  GetLineDistance()
  GetLine()
*/

Macro "network conflation"

  // Input dbds (for testing)
  source_dbd = "C:\\projects/Hickory/HickoryRepo/master/networks/master_network.dbd"
  target_dbd = "C:\\projects/Hickory/HickoryRepo/scenarios/Base_2015/inputs/networks/ScenarioNetwork.dbd"

  // establish an output directory
  a_path = SplitPath(target_dbd)
  output_dir = a_path[1] + a_path[2] + "/conflation"
  if GetDirectoryInfo(output_dir, "All") = null
    then CreateDirectory(output_dir)

  // Make a copy of the source dbd
  from = source_dbd
  source_dbd = output_dir + "/source.dbd"
  CopyDatabase(from, source_dbd)
  from = target_dbd
  target_dbd = output_dir + "/target.dbd"
  CopyDatabase(from, target_dbd)

  // Chop the networks into smaller links
  RunMacro("Chop Network", source_dbd, .25)
  RunMacro("Chop Network", target_dbd, .25)

  // Create a map of the chopped networks
  map = RunMacro("G30 new map", source_dbd)
  {src_nlyr, src_llyr} = GetDBLayers(source_dbd)
  {tgt_nlyr, tgt_llyr} = GetDBLayers(target_dbd)
  tgt_nlyr = AddLayer(map, "target_node", target_dbd, tgt_nlyr)
  tgt_llyr = AddLayer(map, "target_link", target_dbd, tgt_llyr)

  // Add source_id field to target layer
  a_fields = {
    {"source_id", "Integer", 10, ,,,,"ID of link in the source network"}
  }
  RunMacro("Add Fields", tgt_llyr, a_fields)

  // Get a vector of (chopped) link IDs
  v_id = GetDataVector(tgt_llyr + "|", "ID", )
  for i = 1 to v_id.length do
    t_id = v_id[i]

    // Determine the target link's midpoint
    SetLayer(tgt_llyr)
    t_midpoint = RunMacro("get midpoint along line", t_id)

    // Determine the target links's azimuth
    t_coords = GetLine(s_id)
    t_azimuth = Azimuth(t_coords[1], t_coords[t_coords.length])

    // Determine nearest source link to that midpoint and it's midpoint
    SetLayer(src_llyr)
    rh = LocateNearestRecord(t_midpoint, .25, )
    s_id = RH2ID(rh)
    s_midpoint = RunMacro("get midpoint along line", s_id)

    // Check for perfect match
    if t_midpoint.lon = s_midpoint.lon
      and t_midpoint.lat = s_midpoint.lat
      then perfect_match = "True"

    // Continue if not a perfect match
    if !perfect_match then do

        // Get all source links within a search radius
        a_rh = LocateNearestRecords(t_midpoint, .25, )
        dim a_pct[a_rh.length]
        for r = 1 to a_rh.length do
          rh = a_rh[r]

          s_id = RH2ID(rh)
          s_coords = GetLine(s_id)
          a_info = GetLineDistance(t_midpoint, s_coords)
          dist = a_info[1]
        end
    end

  end

EndMacro

/*
This macro will split links until all are beneath the max_length parameter.
The original link ID is preserved a new field - OriginalID - on the network.

Inputs
  dbd
    String
    Full path of the highway geographic file

  max_length
    Real
    Maximum length (in miles) that links can be

Depends
  ModelUtilities
    Add Fields
*/

Macro "Chop Network" (dbd, max_length)

  // Open the dbd in a new map
  map = RunMacro("G30 new map", dbd)
  {nlyr, llyr} = GetDBLayers(dbd)

  // Add field and fill with old ID
  a_fields = {
    {"orig_id", "Integer", 10, ,,,,"ID of link before running 'Chop Network'"}
  }
  RunMacro("Add Fields", llyr, a_fields)
  v_id = GetDataVector(llyr + "|", "ID", )
  SetDataVector(llyr + "|", "orig_id", v_id, )

  // Select all links above the max_length
  SetLayer(llyr)
  qry = "Select * where Length > " + String(max_length)
  n = SelectByQuery("long links", "Several", qry)

  // Repeat the splitting process until no links are > max_length
  CreateProgressBar("Chopping Up Network", "True")
  loop = 1
  while n > 0 do
    // Loop over each link and split in half
    v_ids = GetDataVector(llyr + "|long links", "ID", )
    for i = 1 to v_ids.length do
      id = v_ids[i]
      cancel = UpdateProgressBar(
        "Loop: " + String(loop) +
        " Link: " + String(i) + " of " + String(v_ids.length),
        round(i / v_ids.length * 100, 0)
      )
      if cancel then Throw("Cancel button pressed")

      midpoint = RunMacro("get midpoint along line", id) // hidden TC function
      opts = null
      opts.[Snap to Shape Point] = "False"
      SplitLink(id, midpoint, opts)
    end

    // Check how many links are still above the max_length
    SetLayer(llyr)
    qry = "Select * where Length > " + String(max_length)
    n = SelectByQuery("long links", "Several", qry)

    // Increment the loop variable for the progress bar
    loop = loop + 1
  end

EndMacro
