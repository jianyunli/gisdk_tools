/*
Library of generic tools to update a TransCAD highway network with
project information.

Inputs:
hwyDBD        Highway network to update
projList      CSV file of project IDs
              (A single column titled "ProjID" with a proj ID on each row)
attrList      Array of attribute field names to be updated

Output:
Destructively modifies the input hwyDBD by changing the base attributes
with the project attributes.

Assumptions/Requirements:
The highway network info must be organized in a certain way for this function
to work properly.

1.  Base attribute fields must exist.  For example:

    ABLanes
    BALanes
    PostedSpeed

2.  Project fields must be organized into groups.  A group has a prefix
    which is common to all fields in the group.  A group must have one ID field.
    A group must have the same number of attribute fields as there are base
    fields. For example, a valid group could be:

    prefix = "p1"
    p1ID
    p1ABLanes
    p1BALanes
    p1PostedSpeed

3.  While multiple groups of project fields can exist (p1, p2, etc.), a project
    must exist fully in one group.  This extra restriction makes more advanced
    processing of overlapping projects simpler.

Other Notes:
To code a link for deletion in a project, all project attribute fields
(other than ID) should be set to null.  Similarly, future-year-only links
should have their base year attributes set to null.

Projects listed first in the CSV have priority if two or more projects overlap.
*/

Macro "Select Projects" (hwyDBD, projList, attrList)

  // Get vector of project IDs from the project list file
  csvTbl = OpenTable("tbl", "CSV", {projList, })
  v_projIDs = GetDataVector(csvTbl + "|", "ProjID", )
  CloseView(csvTbl)

  // Determine the project groupings on the highway layer
  projGroups = RunMacro("Determine Project Groups", hwyDBD)

  // Open the highway dbd and add "UpdatedWithP" field
  {nLyr, lLyr} = GetDBLayers(hwyDBD)
  lLyr = AddLayerToWorkspace(lLyr, hwyDBD, lLyr)
  nLyr = AddLayerToWorkspace(nLyr, hwyDBD, nLyr)
  a_fields = {{"UpdatedWithP", "Integer", 10, }}
  RunMacro("TCB Add View Fields", {lLyr, a_fields})

  // Loop over each project ID
  for p = 1 to v_projIDs.length do
    projID = v_projIDs[p]

    // Loop over each project group (group of project fields)
    for g = 1 to projGroups.length do
      projGroup = projGroups[g]

      // Search for the ID in the current group.  Update attributes if found.
      // Do not update if the UpdatedWithP field is already marked with a 1.
      SetLayer(lLyr)
      // Handle possibility of string or integer IDs
      if TypeOf(projID) <> "string" then
        qry = "Select * where " + projGroup + "ID = " + String(projID)
        else qry = "Select * where " + projGroup + "ID = '" + projID + "'"
      qry = qry + " and UpdatedWithP <> 1"
      n = SelectByQuery("updateLinks", "Several", qry)
      if n > 0 then do

        // Loop over each field to update
        for f = 1 to attrList.length do
          baseField = attrList[f]
          projField = projGroup + attrList[f]

          v_vec = GetDataVector(lLyr + "|updateLinks", projField, )
          SetDataVector(lLyr + "|updateLinks", baseField, v_vec, )
        end

        // Mark the UpdatedWithP field to prevent these links from being
        // updated again in subsequent loops.
        opts = null
        opts.Constant = 1
        v_vec = Vector(v_vec.length, "Long", opts)
        SetDataVector(lLyr + "|updateLinks", "UpdatedWithP", v_vec, )
      end
    end
  end

  // Delete links with nulls for all attributes.
  // DeleteRecordsInSet() and DeleteLink() are both slow.
  // Re-export instead.
  SetLayer(lLyr)
  for f = 1 to attrList.length do
    field = attrList[f]
    if f = 1 then qtype = "Several" else qtype = "Subset"

    query = "Select * where " + field + " = null"
    to_del = SelectByQuery("to delete", qtype, query)
  end
  if to_del > 0 then do
    to_exp = SetInvert("to export", "to delete")
    if to_exp = 0 then Throw("No links have attributes")
    a_path = SplitPath(hwyDBD)
    new_dbd = a_path[1] + a_path[2] + a_path[3] + "_temp" + a_path[4]
    {l_names, l_specs} = GetFields(lLyr, "All")
    {n_names, n_specs} = GetFields(nLyr, "All")
    opts = null
    opts.[Field Spec] = l_specs
    opts.[Node Name] = nLyr
    opts.[Node Field Spec] = n_specs
    ExportGeography(lLyr + "|to export", new_dbd, opts)
    DropLayerFromWorkspace(lLyr)
    DropLayerFromWorkspace(nLyr)
    CopyDatabase(new_dbd, hwyDBD)
    DeleteDatabase(new_dbd)
  end

EndMacro

/*
Determines the number of project groups on a network
Assumes groups defined by fields like "p1ID", "p2ID",
"p10ID", etc. (up to "p99ID")
*/

Macro "Determine Project Groups" (hwyDBD)

  {nLyr, lLyr} = GetDBLayers(hwyDBD)
  lLyr = AddLayerToWorkspace(lLyr, hwyDBD, lLyr)
  a_fields = GetFields(lLyr, "All")
  a_fields = a_fields[1]
  projGroups = null
  for f = 1 to a_fields.length do
    field = a_fields[f]

    length = StringLength(field)
    if field[1] = "p" & length <= 5  &
      SubString(field, length - 1, 2) = "ID"
      then projGroups = projGroups + {Substitute(field, "ID", "", )}
  end

  DropLayerFromWorkspace(lLyr)
  return(projGroups)
EndMacro
