require File.dirname(__FILE__) + '/../spec_helper.rb'
require 'aquarium/finders/type_finder'

class Outside
  class Inside1; end
  class Inside2
    class ReallyInside; end
  end
end

describe Aquarium::Finders::TypeFinder, "#find invocation parameters" do

  it "should raise if an uknown option is specified." do
    lambda { Aquarium::Finders::TypeFinder.new.find :foo => 'bar', :baz => ''}.should raise_error(Aquarium::Utils::InvalidOptions)
  end
  
  it "should raise if the input parameters do not form a hash." do
    lambda { Aquarium::Finders::TypeFinder.new.find "foo" }.should raise_error(Aquarium::Utils::InvalidOptions)
  end
  
  it "should return no matched types and no unmatched type expressions by default (i.e., the input is empty)." do
    actual = Aquarium::Finders::TypeFinder.new.find
    actual.matched.should == {}
    actual.not_matched.should == {}
  end
  
  it "should return no matched types and no unmatched type expressions if the input hash is empty." do
    actual = Aquarium::Finders::TypeFinder.new.find {}
    actual.matched.should == {}
    actual.not_matched.should == {}
  end
  
  it "should trim leading and trailing whitespace in the specified types." do
    actual = Aquarium::Finders::TypeFinder.new.find :type => ["  \t ", "\t \n"]
    actual.matched.should == {}
    actual.not_matched.should == {}
  end
  
  it "should ignore an empty string as the specified type." do
    actual = Aquarium::Finders::TypeFinder.new.find :type => "  \t "
    actual.matched.should == {}
    actual.not_matched.should == {}
  end
  
  it "should ignore empty strings as the specified types in an array of types." do
    actual = Aquarium::Finders::TypeFinder.new.find :types => ["  \t ", "\t \n"]
    actual.matched.should == {}
    actual.not_matched.should == {}
  end

  it "should accept a hash and treat it as equivalent to an explicit list parameters." do
    expected_found_types  = [Outside::Inside1, Outside::Inside2]
    expected_unfound_exps = %w[Foo::Bar::Baz]
    hash = {:names => (expected_found_types.map {|t| t.to_s} + expected_unfound_exps)}
    actual = Aquarium::Finders::TypeFinder.new.find hash
    actual.matched_keys.sort_by {|x| x.to_s}.should == expected_found_types.sort_by {|x| x.to_s}
    actual.not_matched_keys.sort.should == expected_unfound_exps.sort
  end
end

describe Aquarium::Finders::TypeFinder, "#is_recognized_option" do
  
  it "should be true for :names, :types, :name, :type (synonyms), as strings or symbols." do
    %w[name type names types].each do |s|
      Aquarium::Finders::TypeFinder.is_recognized_option(s).should == true
      Aquarium::Finders::TypeFinder.is_recognized_option(s.to_sym).should == true
    end
  end  
  
  it "should be false for unknown options." do
    %w[public2 wierd unknown string method object].each do |s|
      Aquarium::Finders::TypeFinder.is_recognized_option(s).should == false
      Aquarium::Finders::TypeFinder.is_recognized_option(s.to_sym).should == false
    end
  end
end


describe Aquarium::Finders::TypeFinder, "#find with :type or :name used to specify a single type" do
  it "should find a type matching a simple name (without :: namespace delimiters) using its name and the :type option." do
    actual = Aquarium::Finders::TypeFinder.new.find :type => :Object
    actual.matched_keys.should == [Object]
    actual.not_matched.should == {}
  end
  
  it "should find a type matching a simple name (without :: namespace delimiters) using its name and the :name option." do
    actual = Aquarium::Finders::TypeFinder.new.find :name => :Object
    actual.matched_keys.should == [Object]
    actual.not_matched.should == {}
  end
  
  it "should return an empty match for a simple name (without :: namespace delimiters) that doesn't match an existing type." do
    actual = Aquarium::Finders::TypeFinder.new.find :name => :Unknown
    actual.matched.should == {}
    actual.not_matched_keys.should == [:Unknown]
  end
  
  it "should find a type matching a name with :: namespace delimiters using its name." do
    actual = Aquarium::Finders::TypeFinder.new.find :name => "Outside::Inside1"
    actual.matched_keys.should == [Outside::Inside1]
    actual.not_matched.should == {}
  end
end
  
describe Aquarium::Finders::TypeFinder, "#find with :types, :names, :type, and :name used to specify one or more names" do
  it "should find types matching simple names (without :: namespace delimiters) using their names." do
    expected_found_types  = [Class, Kernel, Module, Object]
    expected_unfound_exps = %w[TestCase Unknown1 Unknown2]
    actual = Aquarium::Finders::TypeFinder.new.find :types=> %w[Kernel Module Object Class TestCase Unknown1 Unknown2]
    actual.matched_keys.sort.should == expected_found_types.sort
    actual.not_matched_keys.should == expected_unfound_exps
  end

  it "should find types with :: namespace delimiters using their names." do
    expected_found_types  = [Outside::Inside1, Outside::Inside2]
    expected_unfound_exps = %w[Foo::Bar::Baz]
    actual = Aquarium::Finders::TypeFinder.new.find :names => (expected_found_types.map {|t| t.to_s} + expected_unfound_exps)
    actual.matched_keys.sort_by {|x| x.to_s}.should == expected_found_types.sort_by {|x| x.to_s}
    actual.not_matched_keys.sort.should == expected_unfound_exps.sort
  end
end
  
describe Aquarium::Finders::TypeFinder, "#find with :types, :names, :type, and :name used to specify one or more regular expressions" do
  it "should find types matching simple names (without :: namespace delimiters) using lists of regular expressions." do
    expected_found_types  = [Class, Kernel, Module, Object]
    expected_unfound_exps = [/Unknown2/, /^.*TestCase.*$/, /^Unknown1/]
    actual = Aquarium::Finders::TypeFinder.new.find :types => [/K.+l/, /^Mod.+e$/, /^Object$/, /^Clas{2}$/, /^.*TestCase.*$/, /^Unknown1/, /Unknown2/]
    actual.matched_keys.sort_by {|x| x.to_s}.should == expected_found_types.sort_by {|x| x.to_s}
    actual.not_matched_keys.sort.should == expected_unfound_exps.sort
  end
  
  it "should find types matching simple names (without :: namespace delimiters) using regular expressions that match parts of the names." do
    expected_found_types  = [FalseClass, Module, TrueClass]
    expected_unfound_exps = []
    actual = Aquarium::Finders::TypeFinder.new.find :types => [/eClass$/, /^Modu/]
    expected_found_types.each {|t| actual.matched_keys.should include(t)}
    # actual.matched_keys.sort_by {|x| x.to_s}.should == expected_found_types.sort_by {|x| x.to_s}
    actual.not_matched_keys.sort.should == expected_unfound_exps.sort
  end
  
  it "should find types with :: namespace delimiters using lists of regular expressions." do
    expected_found_types  = [Outside::Inside1, Outside::Inside2, Outside::Inside2::ReallyInside]
    expected_unfound_exps = [/^.*Fo+::.*Bar+::Baz.$/]
    actual = Aquarium::Finders::TypeFinder.new.find :types => [/^.*Fo+::.*Bar+::Baz.$/, /Outside::.*1$/, /Out.*::In.*2/, /Out.*::In.*2::R.*/]
    actual.matched_keys.sort_by {|x| x.to_s}.should == expected_found_types.sort_by {|x| x.to_s}
    actual.not_matched_keys.should == expected_unfound_exps
  end
  
  it "should allow a partial trailing name before the first :: namespace delimiter in a regular expression." do
    expected_found_types  = [Outside::Inside1, Outside::Inside2]
    actual = Aquarium::Finders::TypeFinder.new.find :types => [/side::In.*/]
    actual.matched_keys.sort_by {|x| x.to_s}.should == expected_found_types.sort_by {|x| x.to_s}
    actual.not_matched_keys.size.should == 0
  end
  
  it "should allow a partial leading name after the last :: namespace delimiter in a regular expression." do
    expected_found_types  = [Outside::Inside1, Outside::Inside2, Outside::Inside2::ReallyInside]
    actual = Aquarium::Finders::TypeFinder.new.find :types => [/side::In/, /side::Inside2::Real/]
    actual.matched_keys.sort_by {|x| x.to_s}.should == expected_found_types.sort_by {|x| x.to_s}
    actual.not_matched_keys.size.should == 0
  end
  
  it "should require a full name-matching regular expression between :: namespace delimiters." do
    expected_found_types  = [Outside::Inside2::ReallyInside]
    actual = Aquarium::Finders::TypeFinder.new.find :types => [/side::In::Real/]
    actual.matched_keys.size.should == 0
    actual.not_matched_keys.should == [/side::In::Real/]
  end
end

describe Aquarium::Finders::TypeFinder, "#find with :exclude_types" do
  it "should exclude types specified with a regular expression." do
    expected_found_types  = [Class, Module, Object]
    actual = Aquarium::Finders::TypeFinder.new.find :types => [/K.+l/, /^Mod.+e$/, /^Object$/, /^Clas{2}$/], :exclude_types => /^Kernel$/
    actual.matched_keys.sort_by {|x| x.to_s}.should == expected_found_types.sort_by {|x| x.to_s}
    actual.not_matched.size.should == 0
  end

  it "should exclude types specified by name." do
    expected_found_types  = [Class, Module]
    actual = Aquarium::Finders::TypeFinder.new.find :types => [/K.+l/, /^Mod.+e$/, /^Object$/, /^Clas{2}$/], :exclude_types => [Kernel, Object]
    actual.matched_keys.sort_by {|x| x.to_s}.should == expected_found_types.sort_by {|x| x.to_s}
    actual.not_matched.size.should == 0
  end

  it "should not add excluded types to the #not_matched result." do
    expected_found_types  = [Class, Module]
    actual = Aquarium::Finders::TypeFinder.new.find :types => [/K.+l/, /^Mod.+e$/, /^Object$/, /^Clas{2}$/], :exclude_types => [Kernel, Object]
    actual.not_matched.size.should == 0
  end

  it "should be a synonym for :exclude_type." do
    expected_found_types  = [Class, Module]
    actual = Aquarium::Finders::TypeFinder.new.find :types => [/K.+l/, /^Mod.+e$/, /^Object$/, /^Clas{2}$/], :exclude_type => [Kernel, Object]
    actual.matched_keys.sort_by {|x| x.to_s}.should == expected_found_types.sort_by {|x| x.to_s}
    actual.not_matched.size.should == 0
  end

  it "should be a synonym for :exclude_names." do
    expected_found_types  = [Class, Module]
    actual = Aquarium::Finders::TypeFinder.new.find :types => [/K.+l/, /^Mod.+e$/, /^Object$/, /^Clas{2}$/], :exclude_names => [Kernel, Object]
    actual.matched_keys.sort_by {|x| x.to_s}.should == expected_found_types.sort_by {|x| x.to_s}
    actual.not_matched.size.should == 0
  end

  it "should be a synonym for :exclude_name." do
    expected_found_types  = [Class, Module]
    actual = Aquarium::Finders::TypeFinder.new.find :types => [/K.+l/, /^Mod.+e$/, /^Object$/, /^Clas{2}$/], :exclude_name => [Kernel, Object]
    actual.matched_keys.sort_by {|x| x.to_s}.should == expected_found_types.sort_by {|x| x.to_s}
    actual.not_matched.size.should == 0
  end
end
  
describe Aquarium::Finders::TypeFinder, "#find" do
  it "should find types when types given." do
    expected_found_types  = [Outside::Inside1, Outside::Inside2]
    actual = Aquarium::Finders::TypeFinder.new.find :names => expected_found_types
    actual.matched_keys.sort_by {|x| x.to_s}.should == expected_found_types.sort_by {|x| x.to_s}
    actual.not_matched_keys.should == []
  end
end


# This is a spec for a protected method. It's primarily to keep the code coverage 100%, because there is rarely-invoked error handling code...
describe Aquarium::Finders::TypeFinder, "#get_type_from_parent should" do
  it "should raise if a type doesn't exist that matches the constant" do
    lambda {Aquarium::Finders::TypeFinder.new.send(:get_type_from_parent, Aquarium::Finders, "Nonexistent", /Non/)}.should raise_error(NameError)
  end
end
 
  