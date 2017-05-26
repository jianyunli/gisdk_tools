/*
This macro loads count data from a point geographic file onto a highway
line geographic file. (At the bottom of this rsc file is a "test load count"
macro that provides an example.)

Inputs
MacroOpts
  Named array containing all inputs to the function. For example:
  MacroOpts.hwy_dbd = "filepath.dbd"
  
  hwy_dbd
    String
    Full path to the highway line geographic file.

  count_dbd
    String
    Full path to the count point geographic file.
    
  hwy_exclusion_query
    String
    Query definition to exclude certain links from the tagging process.
    Centroid connectors, for example.    
    Can be of the form "Select * where HCMType = 'CC'" or just "HCMType = 'CC'"
    Also recommend removing short links (less than 100 feet).
    
  max_search_dist
    Integer
    Default = 100 feet
    The search radius around the count point. If no links are found within this
    distance, the count will not be loaded onto the network.

  row_dist
    Integer
    Default = 200 feet
    Right of way distance. If an initial link is found within the max_search_dist,
    then a perpendicular line will be drawn to look for other links that might
    be representing the same facility. This variable (row_dist) is the length
    of that line.

  road_name_field
    String (Optional)
    Name of the field that contains road names. When tagging 1-way pairs of
    links, the name field will be used to determine which links are associated
    with the same road. If the first link found is "Highway Eastbound", then a
    link named "Highway Westbound" won't get the count id. Therefore, if
    using this option, make sure that the road name field used calls all links
    representing a single cross section the same thing.
    If not used, all links found within the right of way distance will be
    tagged.
    
    Consider a complex freeway where HOV lanes are represented with separate
    links. If a count point represents total volume on the corridor, then either:
    a.  Don't use the road_name_field or
    b.  Make sure that the road name of all links (general purpose and HOV) are
        the same.
    If you have a point representing HOV volume separate from GP volume, then
    differentiate the road name of the HOV links.
    
    Lastly, this macro performs much better when a road name field is supplied.
    Consider standardizing the road name fields before using. A good strategy is
    to use two road name fields much like addresses are split in 2. The first
    road name field gives the primary name of the road. The second field can
    supply any additional information (like direction, HOV, etc.)
    
  road_lane_fields
    Array of strings
    Array of all field names containing lane information. These fields will be
    added together to get the total number of lanes for each link.  This total
    laneage is used to divide the count volume among multiple links representing
    the same road. This will work even if the lanes are defined by time of day.
    The total will not equal the cross section of the road, but it will
    apportion the count volume correctly.
    
  count_station_field
    String (Optional)
    Name of the field containing the count station ID. This ID field will be
    tagged to to each link representing the same road. If not provided, the
    object ID (the "ID" field) will be used.
    
  count_volume_field
    String
    Name of the field containing the counted volume. The count volume will be
    spread across all links representing the same road according to their
    number of lanes.
*/

Macro "Load Counts" (MacroOpts)
  CreateProgressBar("Loading Counts", "True")
  
  // Extract arguments from MacroOpts
  hwy_dbd = MacroOpts.hwy_dbd
  count_dbd = MacroOpts.count_dbd
  hwy_exclusion_query = MacroOpts.hwy_exclusion_query
  max_search_dist = MacroOpts.max_search_dist
  row_dist = MacroOpts.row_dist
  road_name_field = MacroOpts.road_name_field
  road_lane_fields = MacroOpts.road_lane_fields
  count_station_field = MacroOpts.count_station_field
  count_volume_field = MacroOpts.count_volume_field
  
  // Set default values
  if max_search_dist = null then max_search_dist = 100
  if row_dist = null then row_dist = 200
  if count_station_field = null then count_station_field = "ID"
  
  // Make sure road_lane_fields has only unique names
  opts = null
  opts.Unique = "true"
  test = SortVector(A2V(road_lane_fields), opts)
  if test.length <> road_lane_fields.length
    then Throw("Load Counts: 'road_lane_fields' contains duplicates")

  // Create a minimized map with highway and point layers
  map = RunMacro("G30 new map", hwy_dbd)
  {nlyr, llyr} = GetDBLayers(hwy_dbd)
  {clyr} = GetDBLayers(count_dbd)
  AddLayer(map, clyr, count_dbd, clyr)
  RunMacro("G30 new layer default settings", clyr)
  SetMapUnits("Feet")
  SetSelectDisplay("False")
  MinimizeWindow(GetWindowName())
  
  // Define the file path of line geographic file that will contain the count
  // points converted to line segments. Also, delete it if it already exists.
  a_path = SplitPath(hwy_dbd)
  scratch_dir = a_path[1] + a_path[2]
  scratch_dbd = scratch_dir + "count_lines.dbd"
  if GetFileInfo(scratch_dbd) <> null then DeleteDatabase(scratch_dbd)
  
  // Add count fields to the highway layer.
  // Check to see if the count station id is a string or numeric.
  // Use odd field names to prevent potential overwrite of existing data
  v_temp = GetDataVector(clyr + "|", count_station_field, )
  type = if (TypeOf(v_temp[1])) = "string"
    then "Character"
    else "Integer"
  a_fields = {
    {
      "count_sid_lc", type, 10, ,,,,
      "Count Station ID as tagged by the Load Counts macro"
    },
    {
      "count_vol_lc", "Integer", 10, 3,,,,
      "Count ID as tagged by the Load Counts macro"
    }
  }
  a_initial_values = {null, null}
  RunMacro("Add Fields", llyr, a_fields, a_initial_values)
  
  // Add one field to the count layer that will note any issues encountered
  // during the tagging process.
  a_fields = {
    {
      "check_lc", "Character", 30, ,,,,
      "Reason why a manual check might be necessary"
    }
  }
  a_initial_values = {null}
  RunMacro("Add Fields", clyr, a_fields, a_initial_values)  
  
  // Create a set of links to exclude from tagging
  if Left(hwy_exclusion_query, 15) <> "Select * where "
    then hwy_exclusion_query = "Select * where " + hwy_exclusion_query
  SetLayer(llyr)
  excluded_set = "excluded links"
  n = SelectByQuery(excluded_set, "Several", hwy_exclusion_query)
  if n = 0 then excluded_set = null
  
  // Get a vector of point IDs and count station IDs
  // Loop over each count
  v_cid = GetDataVector(clyr + "|", "ID", )
  v_csid = GetDataVector(clyr + "|", count_station_field, )

  for c = 1 to v_cid.length do
    cid = v_cid[c]
    csid = v_csid[c]
    
    cancelled = UpdateProgressBar(
      "Loading count " + String(c) + " of " + String(v_cid.length),
      round(c / v_cid.length * 100, 0)
    )
    if cancelled then do
      DestroyProgressBar()
      RunMacro("Close All")
      Throw("Count Loading Cancelled")
    end
    
    // Put the current count into its own selection set and get its coordinates
    SetLayer(clyr)
    if ArrayPosition(GetSets(clyr), {current_count_set}, ) > 0
      then DeleteSet(current_count_set)
    current_count_set = CreateSet("current count")
    crh = ID2RH(cid)
    SetRecord(clyr, crh)
    SelectRecord(current_count_set)
    count_coord = Coord(clyr.Longitude, clyr.Latitude)
    
    // Select the nearest link to the current count
    SetLayer(llyr)
    nearest_link_set = "nearest link"
    opts = null
    opts.Inclusion = "Intersecting"
    opts.[Source Not] = excluded_set
    n = SelectNearestFeatures(
      nearest_link_set, "Several", clyr + "|" + current_count_set,
      max_search_dist, opts
    )
    if n = 0 then do
      clyr.check_lc = "no nearest link"
      continue
    end
 
    // Get link id and set it as the current record
    SetLayer(llyr)
    lid = GetSetIDs(llyr + "|" + nearest_link_set)
    lid = lid[1]
    lrh = ID2RH(lid)
    SetRecord(llyr, lrh)
    
    // Mark the check field if the link is < 200 feet. These links can
    // be problematic. Their azimuth may not line up. Often they represent
    // model features that don't line up with real world infrastructure.
    if llyr.Length < 200 then clyr.check_lc = "< 200 ft"
    
    // Determine the azimuth/heading of the link using its endpoints
    a_pts = GetLine(lid)
    az = RunMacro("Get Local Azimuth", count_coord, a_pts)
    
    // Draw a line passing through the count and perpendicular to the
    // nearest link.
    opts = null
    opts.line_dbd = scratch_dbd
    opts.azimuth = az + 90
    opts.line_length = row_dist
    opts.midpoint = count_coord
    opts.identifier = csid
    {perp_id, perp_llyr} = RunMacro("Add Link", opts)
    
    // Place this new link into a fresh selection set
    SetLayer(perp_llyr)
    if ArrayPosition(GetSets(perp_llyr), {current_perp_line_set}, ) > 0
      then DeleteSet(current_perp_line_set)
    current_perp_line_set = CreateSet("current perp line")
    SetRecord(perp_llyr, ID2RH(perp_id))
    SelectRecord(current_perp_line_set)
    
    // Select the roadway links touching the new line
    SetLayer(llyr)
    SetSelectInclusion("Intersecting")
    opts = null
    opts.[Source Not] = excluded_set
    potential_count_links = "potential count links"
    initial = SelectByVicinity(
      potential_count_links,
      "several",
      perp_llyr + "|" + current_perp_line_set,
      null, opts
    )
    // If there are no links found, note that and go to the next count point
    if initial = 0 then do
      clyr.check_lc = "no potential links found"
      continue
    end
    
    // Remove links that don't have the same road name
    if road_name_field <> null then do
      qry = "Select * where " + 
        road_name_field + " <> '" + llyr.(road_name_field) + "'"
      final = SelectByQuery(potential_count_links, "less", qry)
      // Note if links were dropped due to their road name
      if final <> initial then clyr.check_lc = "links dropped by road name"
    end
    
    // Assign the links with the count station ID
    v_temp = GetDataVector(
      llyr + "|" + potential_count_links,
      "count_sid_lc",
      null
    )
    v_temp = if v_temp = null then csid else v_temp
    SetDataVector(
      llyr + "|" + potential_count_links,
      "count_sid_lc",
      v_temp,
      null        
    )
  end  
  
  // Read the count view into a data frame
  count_df = CreateObject("df")
  opts = null
  opts.view = clyr
  opts.fields = {count_station_field, count_volume_field}
  count_df.read_view(opts)
  count_df.rename(count_station_field, "count_sid_lc")
  
  // Read the links tagged with count ids into a data frame
  SetLayer(llyr)
  qry = "Select * where count_sid_lc <> null"
  SelectByQuery("tagged", "several", qry)
  link_df = CreateObject("df")
  opts = null
  opts.view = llyr
  opts.set = "tagged"
  opts.fields = {"ID", "count_sid_lc", "count_vol_lc"} + 
    road_lane_fields
  link_df.read_view(opts)
  
  // calculate total lanes by link (sum the lane columns)
  for f = 1 to road_lane_fields.length do
    field = road_lane_fields[f]
    
    if f = 1 then v = nz(link_df.get_vector(field))
    else v = v + nz(link_df.get_vector(field))
  end
  link_df.mutate("link_lanes", v)
  
  // Create a table with the total lanes grouped by count id
  lanes_by_csid = link_df.copy()
  lanes_by_csid.group_by("count_sid_lc")
  agg = null
  agg.link_lanes = {"sum"}
  lanes_by_csid.summarize(agg)
  
  // Join total lanes onto the link df and calculate percent lanes
  link_df.left_join(lanes_by_csid, "count_sid_lc", "count_sid_lc")
  link_df.left_join(count_df, "count_sid_lc", "count_sid_lc")
  link_df.mutate(
    "pct",
    link_df.get_vector("link_lanes") / link_df.get_vector("sum_link_lanes")
  )
  link_df.mutate(
    "count_vol_lc",
    round(link_df.get_vector(count_volume_field) * link_df.get_vector("pct"), 0)
  )
  
  // Update the link layer with count volume info
  link_df.select("count_vol_lc")
  link_df.update_view(llyr, "tagged")
  
  // Create a unique list of the types of check messages on the link layer
  SetLayer(clyr)
  temp = CreateObject("df")
  v = GetDataVector(clyr + "|", "check_lc", )
  v = temp.unique(v)
  for type in v do
    RunMacro("G30 create set", type)
    qry = "Select * where check_lc = '" + type + "'"
    SelectByQuery(type, "several", qry)
  end
  
  // Clean up the map/workspace
  SetLayer(llyr)
  DeleteSet(nearest_link_set)
  DeleteSet(potential_count_links)
  DeleteSet("tagged")
  SetLayer(clyr)
  DeleteSet(current_count_set)
  MaximizeWindow(GetWindowName())
  RedrawMap(map)
  DestroyProgressBar()
  
  ShowMessage(
    "Count loading finished.\n" + 
    "Use the selection sets on the count point layer\n" +
    "to review potential issues flagged by the process."
  )
EndMacro

/*
This macro was/is used during development, but also serves as
an example of how the "Load Count" macro can be called. 
*/

Macro "test load counts"
  
  RunMacro("Close All")
  RunMacro("Destroy Progress Bars")
  
  dir = "C:\\count_loading"
  opts.hwy_dbd = dir + "/Oahu Network 102907.dbd"
  opts.count_dbd = dir + "/2005 OahuFinalCounts_mar2508.dbd"
  opts.hwy_exclusion_query = "[AB FACTYPE] = 12"
  // opts.max_search_dist = 
  // opts.row_dist = 
  opts.road_name_field = "[Road Name]"
  opts.road_lane_fields = {"AB_LANEA", "BA_LANEA", "AB_LANEM", "BA_LANEM", "AB_LANEP", "BA_LANEP"}
  opts.count_station_field = "ID"
  opts.count_volume_field = "AADT"
  RunMacro("Load Counts", opts)
EndMacro
