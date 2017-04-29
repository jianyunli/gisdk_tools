/*
A general macro for loading information from a count point file onto
a highway link file.

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
    
  max_search_dist
    Integer
    Default = 100 feet
    The search radius around the count point. Links found inside this radius
    will be tagged if they have the same road name.

  road_name_field
    String
    Name of the field that contains road names. When tagging 1-way pairs of
    links, the name field will be used to determine which links are associated
    with the same road. If one link is "Highway Eastbound" and the other is
    "Highway Westbound", the macro will not work correctly. Similarly, use the
    road name field to differentiate (or not) HOV/HOT/shoulder links.
    
  road_lane_fields
    Array of strings
    Array of all field names containing lane information. These fields will be
    added together to get the total number of lanes for each link.  This total
    laneage is used to divide the count volume among multiple links
    representing the same road. This will work even if the lanes are defined by
    time of day. The total will not equal the cross section of the road, but
    it will apportion the count volume correctly.
    
  count_id_field
    String
    Name of the field containing the count ID. This ID field will be tagged to
    to each link representing the same road.
    
  count_volume_field
    String
    Name of the field containing the counted volume. The count volume will be
    spread across all links representing the same road according to their
    number of lanes.
*/
