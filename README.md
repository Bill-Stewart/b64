# b64

Windows command-line utility for encoding data to and decoding data from base64 format

## AUTHOR

Bill Stewart - bstewart at iname dot com

## LICENSE

B64 is covered by the GNU Public License (GPL). See the file `LICENSE` for details.

## DOWNLOAD

https://github.com/Bill-Stewart/b64/releases/

## SYNOPSIS

B64 is a Windows command-line utility that encodes data to and decodes data from base64 format.

## USAGE

**B64** _options_ [**--** ...]

## OPTIONS

| Option                                         | Description
| ------                                         | -----------
| **--encode**[=_filename_], **-e** [_filename_] | Encode to base64
| **--decode**[=_filename_], **-d** [_filename_] | Decode from base64
| **--out=**_filename_, **-o** _filename_        | Write output to file
| **--force**                                    | Overwrite existing output file
| **--newlinetype=**_type_, **-n** _type_        | Encode newline type: **CRLF**, **LF**, or **None**
| **--safe**, **-s**                             | Encode using **-** and **_** (RFC 4648 Sec. 5)
| **--encodestring**, **-E**                     | Encode string after **--** to UTF16 base64
| **--decodestring**, **-D**                     | Decode string after **--** from base64
| **--buffersize=**_n_, **-B** _n_               | Minimum buffer sizes in KB (default=8)
| **--quiet**, **-q**                            | Suppress error messages

## REMARKS

Please note the following:

* Option names are case-sensitive; option arguments are not

* For **--encode** (**-e**) or **--decode** (**-d**), omit filename to encode or decode stdin

* Without **--out** (**-o**), output goes to stdout (not recommended for binary data)

* **--encodestring** (**-E**) and **--decodestring** (**-D**) use command line content after **--**

* The **--buffersize** (**-B**) option specifies a _minimum_ memory buffer size; actual buffer sizes can bw up to 33% larger to accommodate encoding and decoding

* Decodable base64 input containing newlines must meet the following criteria:

  * Line length (except last line) must be a multiple of 4 characters

  * All lines (except last line) must be the same length

  * Lines cannot be longer than 996 characters

  * All newlines must be the same type (CRLF or LF)

  If base64 input with newlines does not meet all of the above criteria, decoding will fail or produce corrupt output

* The output from the **--encodestring** (**-E**) option is suitable for use with the PowerShell **-EncodedCommand** parameter

## OPENSSL COMMAND EQUIVALENTS

This section provides OpenSSL equivalents to b64 commands.

1.  Encode to base64 including newlines:

    `b64 -e` _inputfilename_ `-o` _outputfilename_

    `openssl enc -base64 -e -in` _inputfilename_ `-out` _outputfilename_

    On the Windows platform, OpenSSL uses CRLF newlines, but on non-Windows platforms, it uses LF newlines. If you want to use LF newlines when encoding with b64, use `--newlinetype=LF` (or `-n LF`) with the b64 command; e.g:

    `b64 -e` _inputfilename_ `-o` _outputfilename_ `-n LF`

2.  Encode to base64 without newlines:

    `b64 -e` _inputfilename_ `-o` _outputfilename_ `-n None`

    `openssl enc -base64 -e -in` _inputfilename_ `-out` _outputfilename_ `-A`

3.  Decode from base64:

    `b64 -d` _inputfilename_ `-o` _outputfilename_

    If your base64-encoded file contains newlines, the equivalent OpenSSL command of the above is the following:

    `openssl enc -base64 -d -in` _inputfilename_ `-out` _outputfilename_

    If your base64-encoded file doesn't contain newlines, you must add the `-A` option to decode using OpenSSL; e.g.:

    `openssl enc -base64 -d -in` _inputfilename_ `-out` _outputfilename_ `-A`

    B64 examines the first 998 characters of base64-encoded input and automatically determines the newline type and line length, so it doesn't need an equivalent of the OpenSSL `-A` option. (This automatic determination has its limits, as noted in **REMARKS**.)

One important behavioral difference between b64 and OpenSSL is that OpenSSL will automatically overwrite an output file if it already exists, but b64 will not. (B64 takes a safer route and requires the `--force` option to tell it you really want to overwrite an existing output file.)

## TECHNICAL INFORMATION

B64 uses the following Windows API functions:

*   [**CryptStringToBinaryA**](https://learn.microsoft.com/en-us/windows/win32/api/wincrypt/nf-wincrypt-cryptstringtobinarya) - Decodes base64-encoded input text. The base64-encoded input must be single-byte characters and it must meet the criteria specified in **REMARKS**. B64 uses this function with the **--decode** (**-d**) parameter.

*   [**CryptStringToBinaryW**](https://learn.microsoft.com/en-us/windows/win32/api/wincrypt/nf-wincrypt-cryptstringtobinaryw) - Decodes a base64-encoded Unicode (UTF16LE) string ("LE" stands for "little endian"). B64 uses this function with the **--decodestring** (**-D**) parameter. 

*   [**CryptBinaryToStringA**](https://learn.microsoft.com/en-us/windows/win32/api/wincrypt/nf-wincrypt-cryptbinarytostringa) - Encodes input data to base64-encoded text. The base64 output is single-byte characters. B64 uses this function with the **--encode** (**-e**) parameter. 

*   [**CryptBinaryToStringW**](https://learn.microsoft.com/en-us/windows/win32/api/wincrypt/nf-wincrypt-cryptbinarytostringw) - Encodes a Unicode (UTF16LE) string to a base64-encoded Unicode (UTF16LE) string. The base64 output uses Unicode (UTF16LE) characters. B64 uses this function with the **--encodestring** (**-E**) parameter. 

## EXAMPLES

This section provides some example commands.

1.  Encode a data file to base64 format and save it to a file:

        PS > b64 -e data1.dat -o data1.b64

    The output file will contain 64-character lines and carriage return/line feed (CRLF) line terminators.

2.  Decode the data file back to its original content, with a different name:

        PS > b64 -d data1.b64 -o data2.dat

    You can compare the file hashes to ensure the decoded file contains identical content to the original file:

        PS > (Get-FileHash data1.dat).Hash -eq (Get-FileHash data2.dat).Hash
        True

3.  Output the base64-encoded value of a string you enter at the console:

        PS > b64 --encode
        This is a test
        VGhpcyBpcyBhIHRlc3QNCg==
        ^Z

    Since we didn't specify an input file name, the program waits for input at the console. We enter the string of text, and the program outputs the base64-encoded copy of the string on the next line. To end interactive input, we press `Ctrl+Z` followed by `Enter`.

4.  Create a base64-encoded file from data entered at the console:

        PS > b64 --encode -o test.b64
        This is a test
        ^Z

    As with the previous example, we didn't specify an input file name, so the program waits for input to be entered. As before, we press `Ctrl+Z` followed by `Enter` to end the input. The output file contains the base64-encoded content of the input we entered.

5.  Following the previous example, we want to decode the base64-encoded file to the console:

        PS > b64 -d test.b64
        This is a test

    We didn't specify an output file name, so the program decodes the content to the console.

6.  Encode a command for the PowerShell **-EncodedCommand** parameter:

        PS > cmd /c b64 -E --out=pscu.b64 -- Write-Host `"Test`"

    PowerShell 7.3 changed how PowerShell parses quotes and spaces on its command line, except for a few legacy commands. Executing a command via **cmd /c** bypasses the new behavior for that command. (If you run the command without the **cmd /c** prefix in PowerShell 7.3 and later, PowerShell prefixes quote characters (`"`) with backslash characters (`\`), which we don't want in this case.)

    The **--encodestring** (**-E**) parameter outputs the encoded data as Unicode (UTF16LE), so we must account for this if we want to use the output file with b64 (as in the next example).

7.  Decode the encoded PowerShell command from the previous example:

        PS > Get-Content pscu.b64 -Encoding Unicode |
          Out-File psc.b64 -Encoding ASCII
        PS > b64 -d psc.b64
        Write-Host "Test"

    The first command creates an ASCII-encoded copy of the input Unicode (UTF16) text, and the second command decodes the content of the file.

    Alternatively, we could write it as a single command:

        PS > b64 -D (Get-Content pscu.b64 -Encoding Unicode)
        Write-Host "Test"

    The `(` and `)` surrounding the **Get-Content** command tell PowerShell to evaluate the command within, which happens first. The output of the expression is a Unicode (UTF16) string, which is then used as the argument for b64's **-D** parameter.

8.  Decode a base64-encoded string:

        PS > b64 --decodestring -- SGVsbG8sIHdvcmxk
        Hello, world
