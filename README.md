# Uniprop

UniProp is a gem for managing and analyzing Unicode properties, allowing you to search various information about Unicode properties with a simple code.

## Installation

Install the gem and add to the application's Gemfile by executing:

```
$ bundle add uniprop
```

If bundler is not being used to manage dependencies, install the gem by executing:

```
$ gem install uniprop
```

## Usage
### Basic Usage
```ruby
require 'uniprop'
puts V15.values_of("age", "🧀") #=> 8.0
puts V15.values_of("name", "🧀") #=> CHEESE WEDGE
```
This code is an example of searching for property values of Age and Name properties of the 🧀 emoji in verson 15.0.0.

When uniprop is required, the definition of const_missing is overwritten to make sure that V{num} (e.g. V15) and UNICODE constant match before conventional proccessing.

```ruby
V15_0_0 == V15_0 #=> true
V15_0_0 == V15 #=> true
```
Constants representing versions are denoted by major, minor, and updated versions connected by underscores.
If the minor version or update version is 0, it can be omitted.

### UniString
```ruby
using UniString
"🧀".prop_value("15.0.0", "age") #=> 8.0
"🧀".prop_value("15.0.0", "name") #=> CHEESE WEDGE
```
Writing `using UniString` allows for character-driven searches.

### Searching property values
```ruby
V15.values_of("age", "🧀") #=> 8.0
```
```ruby
using UniString
"🧀".prop_value("15.0.0", "age") #=> 8.0
"🧀".prop.age("15.0.0") #=> 8.0
```

### Searching properties
```ruby
V15.properties_of("🧀", "Yes")
# => ["Emoji", "Emoji_Presentation", "Extended_Pictographic", "Grapheme_Base"]
```
This is the code to get the property with "Yes" defined as the property value of 🧀.

### Searching codepoints
```ruby
V15.codepoints_of("White_Space", "Yes")
# => [9, 10, 11, 12, 13, 32, 133, 160, 5760, 8192, 8193, 8194, 8195, 8196, 8197, 8198, 8199, 8200, 8201, 8202, 8232, 8233, 8239, 8287, 12288]
```

This is the code to get a list of codepoints where "Yes" is defined as the property value of the White_Space property.
Results are output as decimal numbers, not hexadecimal numbers.

### Search Versions
```ruby
UNICODE.versions_of("White_Space", "\u{3000}", "Yes")
#=> ["5.1.0", "5.2.0", "6.0.0", "6.1.0", "6.2.0", "6.3.0", "7.0.0", "8.0.0", "9.0.0", "10.0.0", "11.0.0", "12.0.0", "12.1.0", "13.0.0", "14.0.0", "15.0.0"]
```

This is the code to search for a versions of U+3000 character takes "Yes" as the property value in the White_Space property.

### Search differences between versions
```ruby
UNICODE.value_changed_codepoints("Bidi_Class", "14.0.0", "15.0.0")
```
This is the code to get a list of code points where the property value of the Bidi_Class property has changed in the update from version 14.0.0 to 15.0.0.
The search also takes into account alias spelling inconsistencies of property values.

## File Cache
UniProp automatically downloads the files needed for the search from Unicode. You can search without having to think about caching.

```ruby
ENV["UniPropCache"] = "#{__dir__}/UCD"
```
If you wish to change the path where the cache is stored, change the environment variable above.




