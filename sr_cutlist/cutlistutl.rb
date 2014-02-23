# Some utility definitions of a general scope
# Rather than extend Sketchup base classes which is a dangerous
# practice when the plugin coexists with many other plugins (since all
# plugins would then see the extended class, and/or there might be a 
# conflict if they defined an extension with the same name which might 
# cause one or the other plugin to behave incorrectly, since one method
# would override the other), we define plugin specific methods
# As a general rule, if we wanted to extend String, for example, instead
# we would define a CutList method which takes String as a parameter.
# It's a bit more awkward in the script but avoids the issue of extending
# base classes.
module SteveR
	module CutList
	        @@decimalNotation = ""
		
# 		determine amount of debugging output to the ruby console
		def CutList.verbose1
			false # minimal progress tracking
		end
		
		def CutList.verbose
			false # the whole enchilada - slows down processing considerably - may crash sketchup - use sparingly. turn CutList.verbose on around desired areas
		end
		
		def CutList.verboseComponentDiscovery
			false # trace model entity list traversal only
		end
		
		def CutList.verbosePartPlacement
			false #trace parts placement for layout only
		end
		
		def CutList.verboseParameters
			false # trace parameter passing to/from the GUI
		end
		
		# add a method to return if the current model units is metric
		def CutList.metricModel? 
		  model = Sketchup.active_model

		  # Get the length Units of the active model from the unitsOptions
		  # 0=inches,1=feet,2=mm,3=cm,4=m
		  unit = model.options["UnitsOptions"]["LengthUnit"]
		  return !(unit==0 || unit==1)
		end
  
		def CutList.modelInMeters?
		  model = Sketchup.active_model
		  unit = model.options["UnitsOptions"]["LengthUnit"]
		  return (unit==4)
		end
	  
		# Even if the Sketchup language indicates English 
		# this may not mean that the decimal notation is the English version
		# (where decimal is represented by the '.'. This is because Sketchup
		# defaults to english if the version of Sketchup does not match the
		# language of the operating system. This makes the language of Sketchup
		# unreliable as an indicator of which notation to use.
		# Instead we provide a utility which does a quick check of how Sketchup
		# outputs decimals when converting an internal measurement to to_s notation,.
		# which does seem to be reliable.
		def CutList.initialiseDecimalNotation
			#initialise the class global value for the decimal character
			# and then inspect further to see if this is correct or if
			# it should be the "," character
			@@decimalNotation = "." 
			
			# create a temporary component in the model
			entities = Sketchup.active_model.entities
			definitions = Sketchup.active_model.definitions[0]
			if definitions == NIL
				# if there are no definitions, this method won't work. Use the default value
				puts "CutList::initialiseDecimalNotation - no component definitions"
				puts "Setting decimal notation to en-US"
				return
			end
			
			transformation = Geom::Transformation.new([0,0,0])
			
			# create the temporary component (or group) instance
			componentInstance = entities.add_instance(definitions, transformation)

			# get the bounding box of the created instance
			if componentInstance.respond_to? "definition"
			     boundingBox = componentInstance.definition.bounds
			else
				# is this a group entity? If so, then use our private method to find the definition
				if componentInstance.typename == "Group"
					group_definition = CutList::group_definition(componentInstance)
					boundingBox = group_definition.bounds
					puts "CutList::initialiseDecimalNotation - using bounding box for group"
				else
					# definitions exist but it is neither component nor group
					# unexpected - but return the default in this case as we can't check any more
					# remove the temporary component instance we created above
					entities.erase_entities(componentInstance)
					puts "CutList::initialiseDecimalNotation - no components or groups"
					puts "Setting decimal notation to en-US"
					return
				end
			end
			
			# using our bounding box, arbitrarily use the width value, create a length string out of it
			width = boundingBox.width.inch
			widthString = width.to_l.to_s
			puts "notation test string = " + widthString
			
			# The pattern tests the width string for a "," decimal
			# Set the decimal notation to the same character found in the test string
			pattern = /(\d+)(\,)(\d+)/
			match = widthString.match pattern
			if (match)
				puts "Setting decimal notation to European"
				@@decimalNotation = ","
			else
				puts "Setting decimal notation to en-US"
				@@decimalNotation = "."
			end
			
			# remove the temporary component instance
			entities.erase_entities(componentInstance)
		end
		
		def CutList.decimalNotationInitialised?
			@@decimalNotation != ""
		end
	    
		def CutList.decimalNotation
			CutList::initialiseDecimalNotation if !CutList::decimalNotationInitialised? 
			@@decimalNotation
		end
		
		# method to round a Float to x digits
		def CutList.float_round_to(x, float)
			(float * 10**x).round.to_f / 10**x
		end
		
		# print an integer as a fixed width field of size width.
		# Pads with 0's if too short, it will truncate if too long.
		def CutList.integer_to_fws(width, integer)
		    val="%0#{width}d" % integer.to_s
		end
		# This will html-ise a string so that we don't have problems displaying in html
		# returns a copy of the string with problematic characters replaced by escape sequences
		def CutList.string_to_html(string)
		    val = string.gsub(/[&]/, "&amp;")  #do & first, so we don't convert the conversions!
		    #val = val.gsub(/[']/, "\\\\\'")
		    val = val.gsub(/[ ]/, "&#32;")
		    val = val.gsub(/[']/, "&#39;")
		    val = val.gsub(/["]/, "&quot;")
		    val = val.gsub(/[<]/, "&lt;")
		    val = val.gsub(/[>]/, "&gt;")
		    val = val.gsub(/[-]/, "&#45;")
		    return val
		end 
    
		# cut list plus doesn't like inch character " for inch dimensions on import - these must be  # escaped by doubling them up
		# feet character ie: "'" is interpreted ok
		# mm characters "mm" are interpreted ok
		# cm characters "cm" are interpreted ok
		# units in m are not allowed, so these must be converted prior to this
		def CutList.string_to_clp(string)
		    val = string.gsub(/["]/,"\"\"")
		    #val = val.gsub(/[~]/,"")
		end
  
		# 1, remove the '~' for csv text whether it is straight csv or csv for CLP
		# 2, if a value is in a fraction form and less than 1, then it must be converted 
		# to the format "0 y/z"
		# so that programs like excel convert this to a decimal value instead of text or
		# worse, a date
		# Note: since CLP is also a csv file, it also gets this same conversion. Turns out
		# this is a good thing because CLP has the same problem with fractions < 1 and
		# the solution works for both Excel and CLP
		def CutList.string_to_csv(string)
		#   1. remove the ~
		#     puts "to_csv step 0 val=" + self
		     val = string.gsub(/[~]/,"")
		#     puts "to_csv step 1 val=" + val
		#   2. Determine if this field is a size is in the format "x y/z" and if x="", then insert a 0
		#   The pattern matches on any digits and spaces before a fraction, then the fraction which
		#   consists of any number of digits + "/" + any number of digits - (\d+\/\d+)
		#   (\D*) gobbles up the units at the end and the $ makes sure that the match is at the
		#   endof the string
		#   on a match, match[0] is always the entire match string and match[1..n] are the 
		#   matches of each block, delineated by the brackets.
		#   regexp expression was tested using rubular.com - a Ruby regular expression editor
		     pattern = /(\S*\s)*(\d+\/\d+)(\D*)$/
		     match = val.match pattern
		#    if match == nil
		#	puts "to_csv step 2 match nil" 
		#    else
		#	puts "to_csv step 2 match found" 
		#	puts "match1 is nil" if match[1] == nil 
		#	puts "match1 is " + match[1] if match[1] != nil
		#	puts "match2 is " + match[2] if match[2] != nil
		#	puts "match3 is " + match[3] if match[3] != nil
		#	puts "match4 is " + match[4] if match[4] != nil
		#	end	     
		     if ( match && match[1] == nil && match[2] != nil )
			val="0 " + string
		## DEBUG
		#	puts "to_csv step 3 val=" + val
		## DEBUG
		     end
		     return val
		end
	     
		def CutList.decimal_to_comma(string)
		# convert english numerical represention of decimal "." to european "," if required
			pattern = /(\d+)(\.)(\d+)/
			match = string.match pattern
			if (match )
				val = string.gsub(/[.]/,"#{CutList::decimalNotation}")
				#DEBUG
				#puts "decimal_to_comma: " + string + " converted to " + val
				#DEBUG
				return val
			else
				return string
			end
		end
	     
		#method so that we can reference the definition from which a 
		# group instance has been derived. 
		# (Ideally) xtending the group definition and calling the method 'definition' would make this analagous to 
		# 'definition' method of ComponentInstance
		# However, this is not a nice way of doing it so instead we define a private method to get definition from a group entity
		# Sketchup groups also have a component definition but it's not
		# directly accessible  so we have to start from the model definitions and search
		# looking for the entity which matches ours. Once found we can use it just like
		# for Component Instance
		def CutList.group_definition(group)
		    definitions = Sketchup.active_model.definitions
		    definitions.each { |definition|
		      definition.instances.each { |instance|
			if instance.typename=="Group" && instance == group
			  return definition
			end
		      }
		    }  
		    return nil
		end
	    
		# Returns the current Cutlist Version 
		def  CutList.version
			return "v4.1.11"
		end
	    
	     

	end # module CutLlist
end # module SteveR