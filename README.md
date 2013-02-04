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
      birth_city  string
      birth_date  date
      
Our "requirements" are that the user can never change their birth_date (once the record has been created)...and to contrive
some other requirements - the user can only change their __first_name__ and __last_name__ while the __state__ is 
__initiated__.  Once the workflow state is __in_process__, the user may only change their __birth_city__.

Use the provided DSL to configure attribute control.  Leverage the class method attribute_control to begin the DSL.
The expected parameter value is a hash.  Currently the only hash key expected is __:control_by__ to specify the attribute
that will control the attributes that are allowed to be modified.

      attribute_control(:control_by => :state) do
      end

## always_prevent ##
Use the __always_prevent__ DSL method to specify one or more attribute symbols that should not be modifiable regardless 
of the control_by column value.  For our example, we specify that the SamplePerson's birth_date may not be changed.

      attribute_control(:control_by => :state) do
        always_prevent_change :birth_date        
      end
      
## allow_modification ##
Use the __allow_modification__ DSL method to specify a control_by column value and the columns that may be modified when the
control column is equal to that value.

      attribute_control(:control_by => :state) do
        always_prevent_change :birth_date        
        allow_change_for 'initiated', :attributes => [:first_name, :last_name] 
        allow_change_for 'in_process', :attributes => [:birth_city] 
      end

## has_many associations ##
ChumpChange currently allows for control of associated models one layer deep.  It allows for control of attributes that may
be modified (just like the control of the attributes on the base model).  But it can also exercise control over when associated
objects may be created or deleted from the collection.

      attribute_control(:control_by => :state) do
        always_prevent_change :birth_date        
        allow_change_for 'initiated', { 
          :attributes => [:first_name, :last_name],
          :associations => [ 
                             {
                               :addresses => { 
                                 # Both :allow_create and :allow_delete default to true
                                 :allow_create => true,
                                 :allow_delete => false
                               }
                             }
                           ]
        }
        allow_change_for 'in_process', { 
          :attributes => [:birth_city],
          :associations => [
                             {
                               :addresses => {
                                 :allow_create => false,
                                 :allow_delete => false,
                                 :attributes => [ :street ]
                               }
                             }
                           ]
        }
      end

In the example above, the Person's addresses may be created, but not deleted when the person.state == 'initiated'.  However, 
once the person.state == 'in_process", addresses may no longer be created OR deleted.  Furthermore, only the street address
may be modified.  Apparently, the person is no longer allowed to move from their current city, state, or zip code.  Again, 
perhaps a bit contrived -- but you get the idea.

To implement this functionality, ChumpChange reflects on the has_many association definition and updates the :before_add and
:before_remove options.

## asking the model what can change ##
Some methods that get included with your model when you include the ChumpChange::AttributeGuardian module are:

    allowable_change_fields
    allowable_change_fields_for_<has_many association name>
    allowable_operations_for_<has_many association name>
   
These methods return an array of modifiable attributes based on the current state of the model (specifically the control column value).  If no attributes are currently changeable, then an empty array is returned.
    
### allowable_change_fields ###
In our example, if the person.state == 'initiated, then calling __allowable_change_fields__ would return:

    [ :first_name, :last_name ]

### allowable_change_fields_for_<association_name> ###
In our example, the model has defined an __:addresses__ association.  An available method would be __allowable_change_fields_for_addresses__.  Calling this method when our person.state == 'in_process' would return:

    [ :street ]
    
### allowable_operations_for_<association_name> ###
In our example, the model has defined an __:addresses__ association.  An available method would be __allowable_operations_for_addresses__.  Calling this method when our person.state == 'in_process' would return:

    [ :create ]
    
If the attribute_control DSL were to allow both create and delete operations for an association, this method would return:

    [ :create, :delete ]
    
However, if the person.state == 'in_process', an empty array would be returned.
