# gisdk_tools

These are generic "brick and blocks" for travel demand models written in GISDK for models built in TransCAD.
This repository is intended to be imported as a submodule to other model repos.

  * general tools
    * gplyr
      * data frame, dplyr, and tidyr implemented in GISDK
    * ModelUtilities
      * basic tools helpful in all TC models
  * Generalized model components
    * ProjectManagement
      * Standardizes the approach of a master roadway networking creating scenario networks
    * AreaType
      * Standardizes the approach to calculating area type
    * HCMCapacity
      * Calculates hourly link capacities using HCM2010 formulas
      * Uses the hcmr R package
    * Generation
      * Household Disaggregation
        * Uses the ipfr R package
      * Simple rate model (e.g. for attractions)
      * Cross-classification model
    * Distribution
      * Gravity model
      * Destination Choice
        * Uses the NestedLogitEngine in TC
    * Mode Split
      * Mode Choice
        Uses the NestedLogitEngine in TC (similar approach to DC)

# Installation into your model

1. Add to model repository as a submodule
2. Add the rsc files to the compile.lst file as needed

After that, your project code can call the macros/methods.

# gplyr
Creating a structure in GISDK similar to data frames in R, with methods
that mimic dplyr and tidyr packages.

## Unit testing
A basic set of unit tests is maintained in the macro "test". At least one for each method.  If adding functionality, a unit test must be created to validate the code.  These unit tests will be run before accepting any pull requests.

## Creation
Create a data frame object in GISDK code with the following code

`df = CreateObject("df")`

By default, the data frame is created empty, and one of the input methods below adds data.

## Methods
This section provides a simple list of methods to give an idea of what is available.  A wiki will be created to provide proper documentation and examples for each method.

### Reading / Input
read_view  
read_csv  
read_bin  
read_mtx  
copy

### Writing / Output
write_csv  
write_bin  
create_view  
create_editor

### Manipulation
select  
mutate  
rename  
remove  
group_by  
summarize  
filter  
left_join  
unite  
separate  
spread  
bind_rows

### Utility
is_empty  
nrow  
ncol  
colnames  
check  
in
