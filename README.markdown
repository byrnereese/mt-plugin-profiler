# Overview

This plugin provides a simple way for anyone to audit a Movable Type template
to see why it is so darn slow. The report includes for each template tag found
in the template:

* the name of the template tag
* the number of times it is called
* the average processing time for the tag
* the number of database queries it generates
* the number of cache hits and misses
* the total running time for the tag

The report also provides nice javascript based sorting capabilties to make
it easier to determine the outliers withina given tamplate.

# Known Issues

* Works only with Index Templates right now.

# License

The plugin is licensed under the GPL v2.

# Copyright

* Six Apart, 2008
* Endevver LLC, 2009