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
    
  length
    Real
    Length of the line to add
    
  midpoint
    
    
    
  mapcoordtoxy
  mapxytocoord
*/
