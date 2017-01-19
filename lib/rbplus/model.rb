module EPlusModel

  class Model
    
    def initialize(version)
      @idd_dir = File.join(File.dirname(File.expand_path(__FILE__)), 'idd_files')    
      @version = version.strip
      raise "Fatal: Wrong EnergyPlus version... IDD file not found or not supported" if not File.file? "#{@idd_dir}/#{@version}.idd"
      @idd = IDD.new("#{@idd_dir}/#{@version}.idd")
      @objects = Hash.new

      self.add("version",{"version identifier" => version})
    end

    def get_required_objects_list
      @idd.get_required_objects_list
    end

    def add_from_file(idf_file, object_name_array, other_options )    
      raise "Fatal: File '#{idf_file}' not found" if not File.file? idf_file
      object_name_array.map!{|x| x.downcase} if object_name_array
      other_options = Hash.new if not other_options

      # Default options
      force_required = false

      # process other_options
      force_required = other_options["force required"] if other_options.key? "force required"

      #pre process file
      file = EPlusModel.pre_process_file(idf_file)
      
      #Add objects in file to model     
      file.each{|object|
        object = object.split(",")
        object_name = object.shift.downcase      
        next if object_name == "version"
        
        object_definition = self.get_definition(object_name)
        
        next if (object_name_array and not object_name_array.include? object_name) and  # and this thing is not in the list
                not (object_definition.required and force_required) 

        #initialize the inputs hash
        inputs = Hash.new
        
        object.each_with_index{|value,index|
            next if value.strip == ""
            field = object_definition.fields[index]          
            inputs[field.name] = value      
            inputs[field.name] = inputs[field.name].to_f if field.numeric?   
        } 
        self.add(object_name,inputs)
      }
      return self    
    end

    def add(object_name, inputs)
      object_name.downcase!

      object = get_definition(object_name) #this raises an error if the object does not exist      
      object.check_input(inputs)  #this raises an error if any
      object = object.create(inputs)      

      if object.unique then
        if @objects.key? object_name then
          raise "Trying to replace unique object '#{object_name}'"
        else
          self[object_name] = object     
        end
      else
        if @objects.key? object_name then
          if not self.unique_id?(object.name, object.id) then
            raise "A '#{object_name.capitalize}' called '#{object.id}' already exists"   
          end         
          self[object_name] << object
        else            
          self[object_name] = [object]     
        end
      end
      return object
    end

    def print 
      @objects.each{|key,value|    
        if value.is_a? Array then
          value.each{|i| 
            i.print
            puts ""
          }                  
        else    
          value.print
        end
        puts ""        
      }
    end

    def help(object_name)
      object = @idd[object_name.downcase] #this raises an error if the object does not exist       
      object.help  
    end

    def describe(object_name) 
      object = @idd[object_name.downcase] #this raises an error if the object does not exist       
      puts "!- #{object_name.downcase}"
      puts "!- #{object.memo}"
      puts ""
    end

    def get_definition(object_name)
        @idd[object_name.downcase] #this raises an error if the object does not exist 
    end
    
    def find(query)
      @idd.keys.select{|x| x.downcase.include? query.downcase}      
    end
    
    def [](object_name)
        @objects[object_name.downcase]
    end

    def []=(object_name,object)
        @objects[object_name.downcase] = object
    end

    def get_object_by_id(id)
        @objects.each{|key,object|
            if object.is_a? Array then
                object = object.get_object_by_id(id)
                return object if object
            else
                return value if object.id and object.id.downcase == id.downcase
            end
        }
        return false
    end

    def unique_id?(object_name,id)
      return true if self[object_name] == nil
      return false if self[object_name].map{|x| x.id.downcase}.include? id.downcase 
      return true
    end

    def exists?(object_name,id)
      object = self[object_name]
      return false if object == nil
      if object.is_a? Array then
        object.each{|obj|
          return true if obj.id.downcase == id.downcase
        }
      else
        return true if obj.id.downcase == id.downcase
      end
      return true
    end

    def delete(object_name,id)
      if self[object_name].is_a? Array then
        self[object_name] = self[object_name].select{|x| not x.id.downcase == id.downcase}
      else
        @objects.delete(object_name)
      end
    end


    def get_geometry_from_file(idf_file, other_options)      
      all_geometry =  [  
                        # Required for a correct geometry interpretation
                        "GlobalGeometryRules",

                        #What we want to describe
                        "Zone", 

                        # Surfaces      
                        ## Walls                
                        "Wall:Exterior",
                        "Wall:Adiabatic",
                        "Wall:Underground",
                        "Wall:Interzone",

                        ## Roof / Ceiling
                        "Roof",
                        "Ceiling:Adiabatic",
                        "Ceiling:Interzone",

                        "Floor:GroundContact",
                        "Floor:Adiabatic",
                        "Floor:Interzone",

                        ## Windows/Doors
                        "Window",
                        "Door",
                        "GlazedDoor",
                        "Window:Interzone",
                        "Door:Interzone",
                        "GlazedDoor:Interzone",

                        # Building Surfaces - Detailed
                        "Wall:Detailed",
                        "RoofCeiling:Detailed",
                        "Floor:Detailed",
                        "BuildingSurface:Detailed",                       
                        "FenestrationSurface:Detailed",                       

                        #Internal mass
                        "InternalMass",

                        # Detached shading Surfaces
                        "Shading:Site",
                        "Shading:Building",                      
                        "Shading:Site:Detailed",
                        "Shading:Building:Detailed",

                        # Attached shading surfaces
                        "Shading:Overhang",
                        "Shading:Overhang:Projection",
                        "Shading:Fin",
                        "Shading:Fin:Projection",
                        "Shading:Zone:Detailed",
                        
                      ]
        self.add_from_file(idf_file, all_geometry, other_options)
        return self
    end

    def model_as_storey(options)
        roof_and_ceiling_objects = [        
                                      "Roof",                        
                                      "Ceiling:Adiabatic", 
                                      "Ceiling:Interzone", 
                                      "Floor:GroundContact", 
                                      "Floor:Adiabatic", 
                                      "Floor:Interzone", 
                                      "Buildingsurface:detailed",
                                      "RoofCeiling:Detailed",
                                      "Floor:Detailed",
                              ]

        roof_and_ceiling_objects.each{ |object_name|
            object_array = self[object_name]
            next if not object_array
            object_array.each{ |object|
                # assign the construction                
                case object_name.downcase
                when "buildingsurface:detailed"
                    type = object["Surface Type"].downcase
                    next if not ["floor", "roof", "ceiling"].include? type
                    object["Outside Boundary Condition"]="Adiabatic"            
                    object.delete "Outside Boundary Condition Object"
                when "roofceiling:detailed"
                    object["Outside Boundary Condition"]="Adiabatic"            
                    object.delete "Outside Boundary Condition Object"
                when "floor:detailed"
                    object["Outside Boundary Condition"]="Adiabatic"            
                    object.delete "Outside Boundary Condition Object"
                when "ceiling:adiabatic"
                    warn "'#{obejct.id}' is already adiabatic. Construction was changed anyway."
                when "floor:adiabatic"
                    warn "'#{obejct.id}' is already adiabatic. Construction was changed anyway."
                else
                    warn "'#{object.id}' could not be made adiabatic because it is a '#{object.name.capitalize}'. Construction was changed anyway."
                end
                object["construction name"] = options["assign construction"].id if options
            }
        }
        return self
    end

  end #end of class

end