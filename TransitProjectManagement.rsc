/*
Library of tools to create scenario RTS files by extracting from a master
layer and moving to a scenario network.

Inputs
  MacroOpts
    Named array containing all function arguments

    master_rts
      String
      Full path to the master RTS file
      The RTS file must have a field called ProjID that contains values matching
      the proj_list CSV file.

    scen_hwy
      String
      Full path to the scenario highway dbd that should have the routes loaded

    proj_list
      String
      Full path to the CSV file containing the list of routes to include

Outputs
  Creates a new RTS file in the same folder as scen_hwy
*/

Macro "test"

  opts = null
  opts.master_rts = "Z:\\projects/OahuMPO/Repo/generic/inputs/master_network"
EndMacro
