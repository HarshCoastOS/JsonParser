A Special JSON Parser
=====================

This is a Swift/Cocoa implementation of a special JSON parser. This code is provided as a Swift code example, and as an example how to implement a custom parser.

The original implementation was done in C++/Qt and ported to Swift/Cocoa. This was done for practial reasons, and to see how much the code is simplified using Swift.

- Note the error handling which is done with return tuples which contain the value and an optional error object.
- Access control is also used to protect the implementation details from the public interface.

There were some problems, which made the Swift code complexer as needed:

- Because of the lack of exceptions, the return values got more complex.
- There are no streams to read the string character by character. Instead the string has to converted into an array first. Even in the for loop, there is some way to read the string character by character.
- There was a check "assumeMore()" in the original code, which threw an exception if there were no more characters. There was no way to implement this in the same compact way. Instead there is a quite repetive "if", which tests this condition.

Feel free to fork this code and try to optimize it, to make better use of Swift.
