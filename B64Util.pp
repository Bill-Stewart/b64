{ Copyright (C) 2026 by Bill Stewart (bstewart at iname.com)

  This program is free software: you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free Software
  Foundation, either version 3 of the License, or (at your option) any later
  version.

  This program is distributed in the hope that it will be useful, but WITHOUT
  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
  FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
  details.

  You should have received a copy of the GNU General Public License
  along with this program. If not, see https://www.gnu.org/licenses/.

}

unit B64Util;

{$MODE OBJFPC}
{$MODESWITCH UNICODESTRINGS}

interface

const
  BASE64_MIN_BUFFER_SIZE = $00001000;  // 4KB
  BASE64_DEF_BUFFER_SIZE = $00002000;  // 8KB
  BASE64_MAX_BUFFER_SIZE = $20000000;  // 512MB

type
  TBase64NewlineType = (
    base64NewlineTypeCRLF,
    base64NewlineTypeLF,
    base64NewlineTypeNone
  );

  TB64Util = class
  private
  type
    TBase64BufferInfo = record
      LineLength: Integer;
      NewlineType: TBase64NewlineType;
    end;
  var
    InputFileHandle: THandle;
    OutputFileHandle: THandle;
    Error: DWORD;
    MinBufSize: DWORD;
  procedure SetMinBufferSize(const NewMinBufferSize: DWORD);
  procedure GetDecodeBufferInfo(var Info: TBase64BufferInfo);
  function GetDecodeInputBufferSize(): DWORD;
  procedure GetDecodeOutputBufferSize(const InputBufferSize: DWORD; out OutputBufferSize: DWORD);
  function GetEncodeInputBufferSize(const Flags: DWORD): DWORD;
  procedure GetEncodeOutputBufferSize(const InputBufferSize, Flags: DWORD; out OutputBufferSize: DWORD);

  public
  constructor Create();
  destructor Destroy(); override;
  property MinBufferSize: DWORD write SetMinBufferSize;
  procedure SetInputFile(const FileName: string);
  procedure SetOutputFile(const FileName: string; const ForceOverwrite: Boolean);
  procedure Decode();
  procedure DecodeString(const InputText: string);
  procedure Encode(const NewlineType: TBase64NewlineType; const Safe: Boolean = false);
  procedure EncodeString(const InputText: string; const Safe: Boolean = false);
  property ErrorCode: DWORD read Error;
  end;

implementation

uses
  windows;

const
  BASE64_MIN_LINELENGTH     = 4;
  CRYPTBINARYTOSTRING_WIDTH = 64;  // API only encodes to this width
  CRYPT_STRING_BASE64       = $00000001;
  CRYPT_STRING_BASE64URI    = $0000000D;
  CRYPT_STRING_NOCRLF       = $40000000;
  CRYPT_STRING_NOCR         = $80000000;

type
  TByteArray = array of Byte;
  TUTF8CharArray = array of UTF8Char;

function CryptBinaryToStringA(pbBinary: PByte; cbBinary: DWORD;
  dwFlags: DWORD; pszString: LPSTR; var pcchString: DWORD): BOOL;
  stdcall; external 'crypt32.dll';

function CryptBinaryToStringW(pbBinary: PByte; cbBinary: DWORD;
  dwFlags: DWORD; pszString: LPWSTR; var pcchString: DWORD): BOOL;
  stdcall; external 'crypt32.dll';

function CryptStringToBinaryA(pszString: LPCSTR; cchString: DWORD;
  dwFlags: DWORD; pbBinary: PByte; var pcbBinary: DWORD; pdwSkip: PDWORD;
  pdwFlags: PDWORD): BOOL;
  stdcall; external 'crypt32.dll';

function CryptStringToBinaryW(pszString: LPCWSTR; cchString: DWORD;
  dwFlags: DWORD; pbBinary: PByte; var pcbBinary: DWORD; pdwSkip: PDWORD;
  pdwFlags: PDWORD): BOOL;
  stdcall; external 'crypt32.dll';

constructor TB64Util.Create();
begin
  InputFileHandle := GetStdHandle(STD_INPUT_HANDLE);  // DWORD nStdHandle
  OutputFileHandle := GetStdHandle(STD_OUTPUT_HANDLE);  // DWORD nStdHandle
  Error := ERROR_SUCCESS;
  MinBufSize := BASE64_DEF_BUFFER_SIZE;
end;

destructor TB64Util.Destroy();
begin
  if InputFileHandle <> GetStdHandle(STD_INPUT_HANDLE) then  // DWORD nStdHandle
    CloseHandle(InputFileHandle);  // HANDLE hObject
  if OutputFileHandle <> GetStdHandle(STD_OUTPUT_HANDLE) then  // DWORD nStdHandle
    CloseHandle(OutputFileHandle);  // HANDLE hObject
end;

// Input buffer will be at least this big
procedure TB64Util.SetMinBufferSize(const NewMinBufferSize: DWORD);
begin
  if NewMinBufferSize <= BASE64_MAX_BUFFER_SIZE then
  begin
    MinBufSize := NewMinBufferSize;
    {$IFDEF DEBUG}
    WriteLn(StdErr, 'SetMinBufferSize = ', MinBufSize);
    {$ENDIF}
  end;
end;

procedure TB64Util.SetInputFile(const FileName: string);
begin
  InputFileHandle := CreateFileW(PChar(FileName),  // LPCWSTR               lpFileName
    GENERIC_READ,                                  // DWORD                 dwDesiredAccess
    FILE_SHARE_READ,                               // DWORD                 dwShareMode
    nil,                                           // LPSECURITY_ATTRIBUTES lpSecurityAttributes
    OPEN_EXISTING,                                 // DWORD                 dwCreationDisposition
    FILE_ATTRIBUTE_NORMAL,                         // DWORD                 dwFlagsAndAttributes
    0);                                            // HANDLE                hTemplateFile
  if InputFileHandle = INVALID_HANDLE_VALUE then
    Error := GetLastError();
end;

procedure TB64Util.SetOutputFile(const FileName: string; const ForceOverwrite: Boolean);
var
  CreationDisposition: DWORD;
begin
  if ForceOverwrite then
    CreationDisposition := CREATE_ALWAYS
  else
    CreationDisposition := CREATE_NEW;
  OutputFileHandle := CreateFileW(PChar(FileName),  // LPCWSTR               lpFileName
    GENERIC_WRITE,                                  // DWORD                 dwDesiredAccess
    FILE_SHARE_WRITE,                               // DWORD                 dwShareMode
    nil,                                            // LPSECURITY_ATTRIBUTES lpSecurityAttributes
    CreationDisposition,                            // DWORD                 dwCreationDisposition
    FILE_ATTRIBUTE_NORMAL,                          // DWORD                 dwFlagsAndAttributes
    0);                                             // HANDLE                hTemplateFile
  if OutputFileHandle = INVALID_HANDLE_VALUE then
    Error := GetLastError();
end;

// Read chunk from start of file to determine line length and newline type;
// Info.LineLength will be returned as -1 if no newlines detected
procedure TB64Util.GetDecodeBufferInfo(var Info: TBase64BufferInfo);
const
  MAX_LINE_LEN = 998;  // RFC 5322 (includes trailing newline)
var
  OK: Boolean;
  Buf: array[0..MAX_LINE_LEN - 1] of Byte;
  BytesRead: DWORD;
  P: Integer;
begin
  OK := ReadFile(InputFileHandle,  // HANDLE       hFile
    Buf,                           // LPVOID       lpBuffer
    SizeOf(Buf),                   // DWORD        nNumberOfBytesToRead
    BytesRead,                     // LPDWORD      lpNumberOfBytesRead
    nil);                          // LPOVERLAPPED lpOverlapped
  if OK then
  begin
    P := IndexByte(Buf, BytesRead, 10);  // Look for LF byte
    if (P > 1) and (P <= BytesRead - 1) then
    begin
      // LF found in range Buf[1..BytesRead-1] (2nd through penultimate byte)
      if Buf[P - 1] = 13 then  // See if previous byte is CR
      begin
        Info.NewlineType := base64NewlineTypeCRLF;
        Info.LineLength := P - 1;
      end
      else
      begin
        Info.NewlineType := base64NewlineTypeLF;
        Info.LineLength := P;
      end;
    end
    else
    begin
      Info.NewlineType := base64NewlineTypeNone;
      Info.LineLength := -1;
    end;
    // Reset file pointer back to beginning of file
    if SetFilePointer(InputFileHandle,             // HANDLE hFile
      0,                                           // LONG   lDistanceToMove
      nil,                                         // PLONG  lpDistanceToMoveHigh
      FILE_BEGIN) = INVALID_SET_FILE_POINTER then  // DWORD  dwMoveMethod
    begin
      Error := GetLastError();
    end;
  end
  else
    Error := GetLastError();
  {$IFDEF DEBUG}
  if Error = ERROR_SUCCESS then
  begin
    Write(StdErr, 'DECODE: Newline type = ', Info.NewlineType);
    if Info.NewlineType <> base64NewlineTypeNone then
      Write(StdErr, '  Line length = ', Info.LineLength);
    WriteLn(StdErr, '');
  end;
  {$ENDIF}
end;

function TB64Util.GetDecodeInputBufferSize(): DWORD;
var
  Info: TBase64BufferInfo;
  ChunkSize, I: Integer;
begin
  result := 0;
  GetDecodeBufferInfo(Info);
  // Decode with newlines: Size must be divisible by minimum line length
  if (Info.LineLength <> -1) and (Info.LineLength mod BASE64_MIN_LINELENGTH <> 0) then
  begin
    Error := ERROR_INVALID_DATA;
    exit;
  end;
  case Info.NewlineType of
    base64NewlineTypeLF: ChunkSize := Info.LineLength + 1;
    base64NewlineTypeCRLF: ChunkSize := Info.LineLength + 2;
    else
    begin
      // Decode without newlines: No size adjustment
      ChunkSize := 0;
      result := MinBufSize;
    end;
  end;
  if ChunkSize <> 0 then
  begin
    // Decode with newlines: Size must be divisible by both line length and
    // line length + newlines
    I := MinBufSize;
    while I <= BASE64_MAX_BUFFER_SIZE do
    begin
      if (I mod Info.LineLength = 0) and (I mod ChunkSize = 0) then
      begin
        result := I;
        break;
      end;
      Inc(I, 2);
    end;
  end;
  if result = 0 then
  begin
    Error := ERROR_INSUFFICIENT_BUFFER;
    {$IFDEF DEBUG}
    WriteLn(StdErr, 'GetDecodeInputBufferSize encountered error ', Error);
    {$ENDIF}
  end;
end;

procedure TB64Util.GetDecodeOutputBufferSize(const InputBufferSize: DWORD; out OutputBufferSize: DWORD);
var
  Buf: TUTF8CharArray;
begin
  // Create dummy array and fill with 'a' so the API can tell us the size
  SetLength(Buf, InputBufferSize);
  FillChar(Buf[0], InputBufferSize, #97);
  if not CryptStringToBinaryA(@Buf[0],  // LPCSTR pszString
    InputBufferSize,                    // DWORD  cchString
    CRYPT_STRING_BASE64,                // DWORD  dwFlags
    nil,                                // BYTE   *pbBinary
    OutputBufferSize,                   // DWORD  *pcbBinary
    nil,                                // DWORD  *pdwSkip
    nil) then                           // DWORD  *pwdFlags
  begin
    Error := GetLastError();
  end;
end;

// CryptStringToBinaryA: Decode chunks of base64-encoded text to bytes
procedure TB64Util.Decode();
var
  InBufSize, OutBufSize, BytesRead, BytesToWrite, BytesWritten: DWORD;
  InputByteBuffer, OutputByteBuffer: TByteArray;
  Done: Boolean;
  {$IFDEF DEBUG}
  TotalBytesRead, TotalBytesWritten: QWord;
  {$ENDIF}
begin
  InBufSize := GetDecodeInputBufferSize();
  if Error <> ERROR_SUCCESS then
    exit;
  SetLength(InputByteBuffer, InBufSize);
  GetDecodeOutputBufferSize(InBufSize, OutBufSize);
  if Error <> ERROR_SUCCESS then
    exit;
  SetLength(OutputByteBuffer, OutBufSize);
  {$IFDEF DEBUG}
  WriteLn(StdErr, 'DECODE: Input buffer size = ', InBufSize, '  Output buffer size = ', OutBufSize);
  TotalBytesRead := 0;
  TotalBytesWritten := 0;
  {$ENDIF}
  repeat
    Done := ReadFile(InputFileHandle,  // HANDLE       hFile
      InputByteBuffer[0],              // LPVOID       lpBuffer
      InBufSize,                       // DWORD        nNumberOfBytesToRead
      BytesRead,                       // LPDWORD      lpNumberOfBytesRead
      nil);                            // LPOVERLAPPED lpOverlapped
    if not Done then
      Error := GetLastError();
    Done := (Done and (BytesRead = 0)) or
      ((not Done) and (Error <> ERROR_SUCCESS));
    if not Done then
    begin
      {$IFDEF DEBUG}
      Inc(TotalBytesRead, BytesRead);
      {$ENDIF}
      BytesToWrite := Length(OutputByteBuffer);  // Updated after next call
      if CryptStringToBinaryA(@InputByteBuffer[0],  // LPCSTR pszString
        BytesRead,                                  // DWORD  cchString
        CRYPT_STRING_BASE64,                        // DWORD  dwFlags
        @OutputByteBuffer[0],                       // BYTE   *pbBinary
        BytesToWrite,                               // DWORD  *pcbBinary
        nil,                                        // DWORD  *pdwSkip
        nil) then                                   // DWORD  *pwdFlags
      begin
        if not WriteFile(OutputFileHandle,  // HANDLE       hFile
          OutputByteBuffer[0],              // LPCVOID      lpBuffer
          BytesToWrite,                     // DWORD        nNumberOfBytesToWrite
          BytesWritten,                     // LPDWORD      lpNumberOfBytesWritten
          nil) then                         // LPOVERLAPPED lpOverlapped
        begin
          Error := GetLastError();
          break;
        end;
        {$IFDEF DEBUG}
        Inc(TotalBytesWritten, BytesWritten);
        {$ENDIF}
      end;
    end;
  until Done;
  {$IFDEF DEBUG}
  WriteLn(StdErr, 'Total bytes read = ', TotalBytesRead, '  Total bytes written = ', TotalBytesWritten);
  {$ENDIF}
end;

// CryptStringToBinaryW: Decode base64-encoded Unicode (UTF16LE) string to bytes
procedure TB64Util.DecodeString(const InputText: string);
var
  ByteCount, BytesWritten: DWORD;
  pResult: PChar;
begin
  if CryptStringToBinaryW(PChar(InputText),  // LPCWSTR pszString
    Length(InputText),                       // DWORD   cchString
    CRYPT_STRING_BASE64,                     // DWORD   dwFlags
    nil,                                     // PBYTE   pbBinary
    ByteCount,                               // PDWORD  pcbBinary
    nil,                                     // PDWORD  pdwSkip
    nil) then                                // PDWORD  pdwFlags
  begin
    // Accommodate terminating null
    GetMem(pResult, ByteCount + SizeOf(Char));
    if CryptStringToBinaryW(PChar(InputText),  // LPCWSTR pszString
      Length(InputText),                       // DWORD   cchString
      CRYPT_STRING_BASE64,                     // DWORD   dwflags
      PByte(pResult),                          // PBYTE   pbBinary
      ByteCount,                               // PDWORD  pcbBinary
      nil,                                     // PDWORD  pdwSkip
      nil) then                                // PDWORD  pdwFlags
    begin
      if not WriteFile(OutputFileHandle,  // HANDLE       hFile
        pResult^,                         // LPCVOID      lpBuffer
        ByteCount,                        // DWORD        nNumberOfBytesToWrite
        BytesWritten,                     // LPDWORD      lpNumberOfBytesWritten
        nil) then                         // LPOVERLAPPED lpOverlapped
      begin
        Error := GetLastError();
      end;
    end
    else
      Error := GetLastError();
    FreeMem(pResult);
  end
  else
    Error := GetLastError();
end;

function TB64Util.GetEncodeInputBufferSize(const Flags: DWORD): DWORD;
var
  I: Integer;
begin
  result := 0;
  if Flags and CRYPT_STRING_NOCRLF <> 0 then
  begin
    // Encode without newlines: Size must be a multiple of 3
    I := MinBufSize;
    while I <= BASE64_MAX_BUFFER_SIZE do
    begin
      if I mod 3 = 0 then
      begin
        result := I;
        break;
      end;
      Inc(I, 2);
    end;
  end
  else
  begin
    // Encode with newlines: Size must be multiple of 3 and line length
    I := MinBufSize;
    while I <= BASE64_MAX_BUFFER_SIZE do
    begin
      if (I mod 3 = 0) and (I mod CRYPTBINARYTOSTRING_WIDTH = 0) then
      begin
        result := I;
        break;
      end;
      Inc(I, 2);
    end;
  end;
  if result = 0 then
  begin
    Error := ERROR_INSUFFICIENT_BUFFER;
    {$IFDEF DEBUG}
    WriteLn(StdErr, 'GetEncodeInputBufferSize encountered error ', Error);
    {$ENDIF}
  end;
end;

procedure TB64Util.GetEncodeOutputBufferSize(const InputBufferSize, Flags: DWORD; out OutputBufferSize: DWORD);
var
  Buf: TByteArray;
begin
  // Create dummy array and fill with 'a' so the API can tell us the size
  SetLength(Buf, InputBufferSize);
  FillChar(Buf[0], InputBufferSize, #97);  // Fill with 'a'
  if not CryptBinaryToStringA(@Buf[0],  // PBYTE  pbBinary
    InputBufferSize,                    // DWORD  cbBinary
    Flags,                              // DWORD  dwFlags
    nil,                                // LPSTR  pszString
    OutputBufferSize) then              // DWORD  *pcchString
  begin
    Error := GetLastError();
  end
end;

// CryptBinaryToStringA: Encode chunks of bytes to base64-encoded text
procedure TB64Util.Encode(const NewlineType: TBase64NewlineType; const Safe: Boolean = false);
var
  Flags, InBufSize, OutBufSize, BytesRead, CharsToWrite, BytesWritten: DWORD;
  InputByteBuffer: TByteArray;
  OutputCharBuffer: TUTF8CharArray;
  Done: Boolean;
  {$IFDEF DEBUG}
  TotalBytesRead, TotalBytesWritten: QWord;
  {$ENDIF}
begin
  Flags := CRYPT_STRING_BASE64;
  case NewlineType of
    base64NewlineTypeLF:   Flags := Flags or CRYPT_STRING_NOCR;
    base64NewlineTypeNone: Flags := Flags or CRYPT_STRING_NOCRLF;
  end;
  if Safe then
    Flags := Flags or CRYPT_STRING_BASE64URI;
  InBufSize := GetEncodeInputBufferSize(Flags);
  if Error <> ERROR_SUCCESS then
    exit;
  SetLength(InputByteBuffer, InBufSize);
  GetEncodeOutputBufferSize(InBufSize, Flags, OutBufSize);
  if Error <> ERROR_SUCCESS then
    exit;
  SetLength(OutputCharBuffer, OutBufSize);
  {$IFDEF DEBUG}
  WriteLn(StdErr, 'ENCODE: Input buffer size = ', InBufSize, '  Output buffer size = ', OutBufSize);
  TotalBytesRead := 0;
  TotalBytesWritten := 0;
  {$ENDIF}
  repeat
    Done := ReadFile(InputFileHandle,  // HANDLE       hFile
      InputByteBuffer[0],              // LPVOID       lpBuffer
      InBufSize,                       // DWORD        nNumberOfBytesToRead
      BytesRead,                       // LPDWORD      lpNumberOfBytesRead
      nil);                            // LPOVERLAPPED lpOverlapped
    if not Done then
      Error := GetLastError();
    Done := (Done and (BytesRead = 0)) or
      ((not Done) and (Error <> ERROR_SUCCESS));
    if not Done then
    begin
      {$IFDEF DEBUG}
      Inc(TotalBytesRead, BytesRead);
      {$ENDIF}
      CharsToWrite := Length(OutputCharBuffer);  // Updated after next call
      if CryptBinaryToStringA(@InputByteBuffer[0],  // PBYTE  pbBinary
        BytesRead,                                  // DWORD  cbBinary
        Flags,                                      // DWORD  dwflags
        @OutputCharBuffer[0],                       // LPSTR  pszString
        CharsToWrite) then                          // PDWORD pcchString
      begin
        if not WriteFile(OutputFileHandle,  // HANDLE       hFile
          OutputCharBuffer[0],              // LPCVOID      lpBuffer
          CharsToWrite,                     // DWORD        nNumberOfBytesToWrite
          BytesWritten,                     // LPDWORD      lpNumberOfBytesWritten
          nil) then                         // LPOVERLAPPED lpOverlapped
        begin
          Error := GetLastError();
          break;
        end;
        {$IFDEF DEBUG}
        Inc(TotalBytesWritten, BytesWritten);
        {$ENDIF}
      end;
    end;
  until Done;
  {$IFDEF DEBUG}
  WriteLn(StdErr, 'Total bytes read = ', TotalBytesRead, '  Total bytes written = ', TotalBytesWritten);
  {$ENDIF}
end;

// CryptBinaryToStringW: Encode Unicode (UTF16LE) string to base64-encoded text
procedure TB64Util.EncodeString(const InputText: string; const Safe: Boolean = false);
var
  InputTextLength, Flags, NumChars, BytesWritten: DWORD;
  pResult: PChar;
begin
  InputTextLength := Length(InputText) * SizeOf(Char);  // Need byte length
  Flags := CRYPT_STRING_BASE64 or CRYPT_STRING_NOCRLF;
  if Safe then
    Flags := Flags or CRYPT_STRING_BASE64URI;
  if CryptBinaryToStringW(PByte(InputText),  // PBYTE  pbBinary
    InputTextLength,                         // DWORD  cbBinary
    Flags,                                   // DWORD  dwflags
    nil,                                     // LPWSTR pszString
    NumChars) then                           // PDWORD pcchString
  begin
    // Allocate sufficient buffer size
    GetMem(pResult, NumChars * SizeOf(Char));
    if CryptBinaryToStringW(PByte(InputText),  // PBYTE  pbBinary
      InputTextLength,                         // DWORD  cbBinary
      Flags,                                   // DWORD  dwFlags
      pResult,                                 // LPWSTR pszString
      NumChars) then                           // PDWORD pcchString
    begin
      if not WriteFile(OutputFileHandle,  // HANDLE       hFile
        pResult^,                         // LPCVOID      lpBuffer
        NumChars * SizeOf(Char),          // DWORD        nNumberOfBytesToWrite
        BytesWritten,                     // LPDWORD      lpNumberOfBytesWritten
        nil) then                         // LPOVERLAPPED lpOverlapped
      begin
        Error := GetLastError();
      end;
    end
    else
      Error := GetLastError();
    FreeMem(pResult);
  end
  else
    Error := GetLastError();
end;

begin
end.
