/*
This macro loads count data from a point geographic file onto a highway
line geographic file.

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
    Default = 100 feet
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
  if row_dist = null then row_dist = 100
  if count_station_field = null then count_station_field = "ID"
  
  // Create a minimized map with highway and point layers
  map = RunMacro("G30 new map", hwy_dbd)
  {nlyr, llyr} = GetDBLayers(hwy_dbd)
  {clyr} = GetDBLayers(count_dbd)
  AddLayer(map, clyr, count_dbd, clyr)
  SetMapUnits("Feet")
  SetSelectDisplay("False")
  MinimizeWindow(GetWindowName())
  
  // Add count fields to the highway layer.
  // Check to see if the count station id is a string or numeric.
  // Use odd field names to prevent potential overwrite of existing data
  v_temp = GetDataVector(clyr + "|", count_station_field, )
  type = if (TypeOf(v_temp[1])) = "string"
    then "Character"
    else "Integer"
  a_fields = {
    {"count_sid_lc", type, 10, ,,,,"Count Station ID as tagged by the Load Counts macro"},
    {"count_vol_lc", "Integer", 10, 3,,,,"Count ID as tagged by the Load Counts macro"},
    {"check_lc", "Character", 30, ,,,,"Reason why a manual check might be necessary"}
  }
  a_initial_values = {null, null}
  RunMacro("Add Fields", llyr, a_fields, a_initial_values)
  
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
    
    // Put the current count into its own selection set and get its coordinates
    SetLayer(clyr)
    if ArrayPosition(GetSets(clyr), {current_count_set}) > 0
      then DeleteSet(current_count_set)
    current_count_set = CreateSet("current count")
    crh = ID2RH(cid)
    SelectRecord(crh)
    SetRecord(crh)
    count_coord = Coord(clyr.Longitude, clyr.Latitude)
    
    // Select the nearest link to the current count
    SetLayer(llyr)
    nearest_link_set = "nearest link"
    opts = null
    opts.Inclusion = "Intersecting"
    opts.[Source Not] = excluded_set
    n = SelectNearestFeatures(
      nearest_link_set, "Several", clyr + "|" + current_count_set,
      max_search_dist, opts)
    
    // Continue if a link was selected
    if n > 0 then do
      // Get link id and set it as the current record
      SetLayer(llyr)
      lid = GetSetIDs(llyr + "|" + nearest_link_set)
      lid = lid[1]
      lrh = ID2RH(lid)
      SetRecord(lrh)
      
      // Mark the check field if the link is < 200 feet. These links can
      // be problematic. Their azimuth may not line up. Often they represent
      // model features that don't line up with real world infrastructure.
      if llyr.Length < 200 then llyr.check_lc = "< 200 ft"
      
      // Determine the azimuth/heading of the link using its endpoints
      a_pts = GetLine(lid)
      az = Azimuth(a_pts[1], a_pts[a_pts.length])
      
      // Draw a line passing through the count and perpendicular to the
      // nearest link.
      opts = null
      opts.line_dbd = 
      opts.azimuth = az + 90
      opts.length = row_dist
      opts.midpoint = count_coord
      opts.identifier = csid
      RunMacro("Add Link")
    
    end
    
    SelectRecord()
    
  end
  
  
  
EndMacro
