chumpchange
===========

Simple gem that provides a DSL to control ActiveRecord model changes.

This gem grew out of time that I spent working on a workflow-based system.  Our models used a __:state__ column that 
indicated where the model instance was in the workflow. Example states are __initiated__, __in_process__, 
and __completed__.  Our requirements were to only allow changes to specific attributes when the workflow was in a given 
state.  Out of these requirements came this gem.

When attempting changes to a model configured with __chumpchange__, ActiveRecord's before_save hook is used to call a
method provided by the gem.  The method called evaluates the attributes that have been modified and will raise an 
exception if any attributes have been modified that are in conflict with the DSL configuration.

To use the gem:

Include the ChumpChange::AttributeGuardian in your model class.

      class SamplePerson < ActiveRecord:Base
        include ChumpChange::AttributeGuardian
        
For the sake of this example, let's assume that we have a table that backs our model with the following attributes:

      first_name  string
      last_name   string
      home_city   string
      birth_date  date
      
Our "requirements" are that the user can never change their birth_date (once the record has been created)...and to contrive
some other requirements - the user can only change their __first_name__ and __last_name__ while the __state__ is 
__initiated__.  Once the workflow state is __in_process__, the user may only change their __home_city__.

Use the provided DSL to configure attribute control.  Leverage the class method attribute_control to begin the DSL.
The expected parameter value is a hash.  Currently the only hash key expected is __:control_by__ to specify the attribute
that will control the attributes that are allowed to be modified.

      attribute_control({:control_by => 'state'}) do
      end

## always_prevent ##
Use the __always_prevent__ DSL method to specify one or more attribute symbols that should not be modifiable regardless 
of the control_by column value.  For our example, we specify that the SamplePerson's birth_date may not be changed.

      attribute_control({:control_by => 'state'}) do
        always_prevent :birth_date        
      end
      
## allow_modification ##
Use the __allow_modification__ DSL method to specify a control_by column value and the columns that may be modified when the
control column is equal to that value.

      attribute_control({:control_by => 'state'}) do
        always_prevent :birth_date        
        allow_modification 'initiated', :first_name, :last_name
        allow_modification 'in_process', :home_city
      end

     
