/*
This script contains basic functions that are helpful to lots of different
network-related tasks. Storing them here adds a little more organization to
the net_tools folder.

Rather than place these functions in the ModelUtilities.rsc file, this file
is the first attempt to organize utility functions by type/purpose. Eventually,
the ModelUtilities.rsc file should be split up, as it is becoming too large.
*/

/*
Improves on the basic GISDK AddLink() function by adding some easier to use
options. A line can be defined with a midpoint, azimuth, and length. This macro
can be expanded to include other definition options. If you have a list of
coordinates, just use AddLink() directly.

MacroOpts
  Named array containing all arguments for the function

  line_dbd
    String
    Full path to the line geographic file where the line should be added. If the
    DBD is already open, the line will be added to the layer. If the DBD does
    not exist, one will be created.

  azimuth
    Real
    Angle, in degrees, of the line.

  line_length
    Real
    Length of the line to add

  midpoint
    Coordinate object
    The coordinate of the midpoint of the line

Returns
  ID of the newly-created link

*/

Macro "Add Link" (MacroOpts)

  // Extract arguments from MacroOpts
  line_dbd = MacroOpts.line_dbd
  azimuth = MacroOpts.azimuth
  line_length = MacroOpts.line_length
  midpoint = MacroOpts.midpoint

  // Argument check
  if line_dbd = null then Throw("'line_dbd' is missing")
  if azimuth = null then Throw("'azimuth' is missing")
  if line_length = null then Throw("'line_length' is missing")
  if midpoint = null then Throw("'midpoint' is missing")
  // Make sure azimuth is between 0 and 360
  azimuth = Mod(azimuth, 360)

  // Determine if the line_dbd needs to be created (if it is not a layer
  // in the current map)
  create_line_dbd = "true"
  map = GetMap()
  if map <> null then do
    a_layers = GetMapLayers(map, "All")
    a_layers = a_layers[1]
    for l = 1 to a_layers.length do
      layer = a_layers[l]

      check_dbd = GetLayerDB(layer)
      // GetLayerDB() returns a string with "\"s and extension ".DBD".
      // Make sure line_dbd looks the same way before checking.
      line_dbd = Substitute(line_dbd, "/", "\\", )
      line_dbd = Substitute(line_dbd, ".dbd", ".DBD", )
      if check_dbd = line_dbd then do
        create_line_dbd = "false"
        {nlyr, llyr} = GetDBLayers(line_dbd)
      end
    end
  end

  // If needed, create line_dbd geographic file that will contain the
  // count points converted to line segments.
  if create_line_dbd then do
    opts = null
    opts.Label = "Count points converted to lines"
    opts.[Layer Name] = "Count Lines"
    opts.[Node Layer Name] = "Count Line Nodes"
    CreateDatabase(line_dbd, "Line", opts)
    {nlyr, llyr} = GetDBLayers(line_dbd)

    // If no map is present, create one
    if map = null then map = RunMacro("G30 new map", line_dbd)
    // otherwise, add the new layers to the map
    else do
      AddLayer(map, nlyr, line_dbd, nlyr)
      AddLayer(map, llyr, line_dbd, llyr)
      RunMacro("G30 new layer default settings", nlyr)
      RunMacro("G30 new layer default settings", llyr)
    end
  end

  /*
  Determine which quadrant the angle is in. TC sets 0 degrees as
  due north so the quadrants look like so:

  4   |   1
  ---------
  3   |   2
  */
  quadrant = Ceil(azimuth / 90)
  {midpoint_x, midpoint_y} = MapCoordToXY(map, midpoint)
  pi = 3.14159

  // Once converted to XY coordinates, the units are meters.
  // Must convert line_length to meters.
  line_length = line_length * .3048

  // TransCAD Sin() and Cos() work in radians, so must convert.
  // 360 degrees = 2pi radians
  // 180 degrees =  pi radians
  angle_radians = azimuth * pi / 180

  // If in quadrant 1
  if quadrant = 1 then do
    x_delta = Sin(angle_radians) * (line_length / 2)
    y_delta = Cos(angle_radians) * (line_length / 2)
  end

  // If in quadrant 2
  if quadrant = 2 then do
    x_delta = Sin(pi - angle_radians) * (line_length / 2)
    y_delta = (Cos(pi - angle_radians) * (line_length / 2)) * -1
  end

  // If in quadrant 3
  if quadrant = 3 then do
    x_delta = (Sin(angle_radians - pi) * (line_length / 2)) * -1
    y_delta = (Cos(angle_radians - pi) * (line_length / 2)) * -1
  end

  // If in quadrant 4
  if quadrant = 4 then do
    x_delta = (Sin(2 * pi - angle_radians) * (line_length / 2)) * -1
    y_delta = Cos(2 * pi - angle_radians) * (line_length / 2)
  end

  x1 = midpoint_x + x_delta
  y1 = midpoint_y + y_delta
  x2 = midpoint_x - x_delta
  y2 = midpoint_y - y_delta
  coord_e1 = MapXYToCoord(map, {x1, y1})
  coord_e2 = MapXYToCoord(map, {x2, y2})

  // Add the link
  SetLayer(llyr)
  a_returned = AddLink({coord_e1, coord_e2}, , )
  new_id = a_returned[1]

  return({new_id, llyr})
EndMacro

/*
Given a point and the array of shape points returned by GetLine() for the
nearest line segment, return the azimuth/heading of the nearest 2 shape points.

Inputs
  point
    Coordinate
    Coordinate of the count point

  line_points
    Array of coordinates returned by GetLine()
*/

Macro "Get Local Azimuth" (point, line_points)

  // Determine the two shape points nearest to the point
  a_dist = {999999999, 999999999}
  dim a_pts[2]
  for p = 1 to line_points.length do
    line_point = line_points[p]

    dist = GetDistance(point, line_point)
    if dist < a_dist[1] then do
      a_dist[2] = a_dist[1]
      a_pts[2] = a_pts[1]
      a_dist[1] = dist
      a_pts[1] = line_point
    end else if dist < a_dist[2] then do
      a_dist[2] = dist
      a_pts[2] = line_point
    end
  end

  // Get the azimuth of the two nearest points
  az = Azimuth(a_pts[1], a_pts[2])

  return(az)
EndMacro


/*
Makes a copy of all the files comprising a route system.
Optionally includes the highway dbd.

Inputs

  MacroOpts
    Named array containing all argument macros

    from_rts
      String
      Full path to the route system to copy. Ends in ".rts"

    to_dir
      String
      Full path to the directory where files will be copied

    include_hwy_files
      Optional True/False
      Whether to also copy the highway files. Defaults to false. Because of the
      fragile nature of the RTS file, the highway layer is first assumed to be
      in the same folder as the RTS file. If it isn't, GetRouteSystemInfo() will
      be used to try and locate it; however, this method is prone to errors if
      the route system is in different places on different machines. As a general
      rule, always keep the highway layer and the RTS layer together.

Returns
  rts_file
    String
    Full path to the resulting .RTS file
*/

Macro "Copy RTS Files" (MacroOpts)

  // Argument extraction
  from_rts = MacroOpts.from_rts
  to_dir = MacroOpts.to_dir
  include_hwy_files = MacroOpts.include_hwy_files

  // Argument check
  if from_rts = null then Throw("Copy RTS Files: 'from_rts' not provided")
  if to_dir = null then Throw("Copy RTS Files: 'to_dir' not provided")
  to_dir = RunMacro("Normalize Path", to_dir)

  // Get the directory containing from_rts
  a_rts_path = SplitPath(from_rts)
  from_dir = RunMacro("Normalize Path", a_rts_path[1] + a_rts_path[2])
  to_rts = to_dir + "/" + a_rts_path[3] + a_rts_path[4]

  // Create to_dir if it doesn't exist
  if GetDirectoryInfo(to_dir, "All") = null then CreateDirectory(to_dir)

  // Get all files comprising the route system
  {a_names, a_sizes} = GetRouteSystemFiles(from_rts)
  for file_name in a_names do
    from_file = from_dir + "/" + file_name
    to_file = to_dir + "/" + file_name
    CopyFile(from_file, to_file)
  end

  // If also copying the highway files
  if include_hwy_files then do

    // Get the highway file. Use gisdk_tools macro to avoid common errors
    // with GetRouteSystemInfo()
    opts = null
    opts.rts_file = from_rts
    from_hwy_dbd = RunMacro("Get RTS Highway File", opts)

    // Use the to_dir to create the path to copy to
    a_path = SplitPath(from_hwy_dbd)
    to_hwy_dbd = to_dir + "/" + a_path[3] + a_path[4]

    CopyDatabase(from_hwy_dbd, to_hwy_dbd)

    // Change the to_rts to point to the to_hwy_dbd
    {nlyr, llyr} = GetDBLayers(to_hwy_dbd)
    ModifyRouteSystem(
      to_rts,{
        {"Geography", to_hwy_dbd, llyr},
        {"Link ID", "ID"}
      }
    )

    // Return both resulting RTS and DBD
    return({to_rts, to_hwy_dbd})
  end

  // Return the resulting RTS file
  return(to_rts)
EndMacro

/*
Because of the fragile nature of the RTS file, GetRouteSystemInfo() can often
return highway file paths that are incorrect. This macro checks to see if the
highway file returned by GetRouteSystemInfo() exists. If not, it looks in the
directory of the route system file.

Inputs
  MacroOpts
    Named array that holds macro arguments

    rts_file
      String
      Full path to the RTS file whose highway file you want to locate.

Returns
  String - full path to the highway file associated with the RTS.
*/

Macro "Get RTS Highway File" (MacroOpts)

  // Argument extraction
  rts_file = MacroOpts.rts_file

  // Argument checking
  if rts_file = null then Throw("Get RTS Highway File: 'rts_file' not provided")

  // Start by assuming the route system info is correct
  a_rts_info = GetRouteSystemInfo(rts_file)
  hwy_dbd = a_rts_info[1]

  // If the highway file does not exist at the path according to the rts file,
  // assume it is in the same directory as the RTS.
  // Use the RTS file to get the name of the highway file.
  if GetFileInfo(hwy_dbd) = null then do
    a_path = SplitPath(hwy_dbd)
    a_rts_path = SplitPath(rts_file)
    hwy_dbd = a_rts_path[1] + a_rts_path[2] + a_path[3] + a_path[4]
  end

  // If there is no file at that path, throw an error message
  if GetFileInfo(hwy_dbd) = null
    then Throw(
      "Get RTS Highway File: The highway network associated with this RTS\n" +
      "cannot be found in the same directory as the RTS nor at: \n" +
      hwy_dbd
    )

  return(hwy_dbd)
EndMacro
