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

program b64;

{$MODE OBJFPC}
{$MODESWITCH UNICODESTRINGS}
{$R *.res}

uses
  windows,
  wargcv,           // https://github.com/Bill-Stewart/wargcv
  wgetopts,         // https://github.com/Bill-Stewart/wargcv
  WindowsMessages,  // https://github.com/Bill-Stewart/WindowsMessages
  WindowsString,    // https://github.com/Bill-Stewart/WindowsString
  B64Util;

const
  PROGRAM_NAME = 'b64';
  PROGRAM_COPYRIGHT = 'Copyright (C) 2026 by Bill Stewart';

type
  TBase64Action = (
    b64ActionDecode,        // --decode (-d)
    b64ActionDecodeString,  // --decodestring (-D)
    b64ActionEncode,        // --encode (-e)
    b64ActionEncodeString   // --encodestring (-E)
  );
  TBase64ActionSet = set of TBase64Action;

  TCommandLine = object
    ActionSet: TBase64ActionSet;
    Error: DWORD;
    ErrorMsg: string;
    InputFileName: string;
    OutputFileName: string;
    MinBufSize: Integer;
    NewlineType: TBase64NewlineType;
    UTF16Str: string;
    ForceOverwrite: Boolean;
    Help: Boolean;
    Quiet: Boolean;
    Safe: Boolean;
    procedure Parse();
  end;

function IntToStr(const I: Integer): string;
begin
  Str(I, result);
end;

function GetFileVersion(const FileName: string): string;
var
  VerInfoSize, Handle: DWORD;
  pBuffer: Pointer;
  pFileInfo: ^VS_FIXEDFILEINFO;
  Len: UINT;
begin
  result := '';
  VerInfoSize := GetFileVersionInfoSizeW(PChar(FileName),  // LPCWSTR lptstrFilename
    Handle);                                               // LPDWORD lpdwHandle
  if VerInfoSize > 0 then
  begin
    GetMem(pBuffer, VerInfoSize);
    if GetFileVersionInfoW(PChar(FileName),  // LPCWSTR lptstrFilename
      Handle,                                // DWORD   dwHandle
      VerInfoSize,                           // DWORD   dwLen
      pBuffer) then                          // LPVOID  lpData
    begin
      if VerQueryValueW(pBuffer,  // LPCVOID pBlock
        '\',                      // LPCWSTR lpSubBlock
        pFileInfo,                // LPVOID  *lplpBuffer
        Len) then                 // PUINT   puLen
      begin
        with pFileInfo^ do
        begin
          result := IntToStr(HiWord(dwFileVersionMS)) + '.' +
            IntToStr(LoWord(dwFileVersionMS)) + '.' +
            IntToStr(HiWord(dwFileVersionLS));
        end;
      end;
    end;
    FreeMem(pBuffer);
  end;
end;

procedure Usage();
begin
  WriteLn(PROGRAM_NAME, ' ', GetFileVersion(ParamStr(0)), ' - ', PROGRAM_COPYRIGHT);
  WriteLn('This is free software and comes with ABSOLUTELY NO WARRANTY.');
  WriteLn();
  WriteLn('SYNOPSIS');
  WriteLn();
  WriteLn('Encodes data to and decodes data from base64 format.');
  WriteLn();
  WriteLn('USAGE');
  WriteLn();
  WriteLn('b64 --encode[=<filename>] [--out=<filename> [--force]] [--newlinetype=<type>]');
  WriteLn('[--safe] [--quiet]');
  WriteLn();
  WriteLn('b64 --decode[=<filename>] [--out=<filename> [--force]] [--quiet]');
  WriteLn();
  WriteLn('b64 --encodestring [--out=<filename> [--force]] [--quiet] -- <string> [...]');
  WriteLn();
  WriteLn('b64 --decodestring [--out=<filename> [--force]] [--quiet] -- <string>');
  WriteLn();
  WriteLn('PARAMETERS');
  WriteLn();
  WriteLn('Parameters are case-sensitive.');
  WriteLn();
  WriteLn('--encode[=<filename>] or -e [<filename>] - Encode content to base64. Omit a');
  WriteLn('file name to encode the content of standard input. Enclose the filename between');
  WriteLn('" characters if it contains whitespace.');
  WriteLn();
  WriteLn('--newlinetype=<type> or -n <type> - Set the newline type for encoded base64');
  WriteLn('output. The <type> argument is not case-sensitive and is one of: "CRLF"');
  WriteLn('(carriage return/linefeed--Windows style), "LF" (linefeed--Unix style), or');
  WriteLn('"None" (no newlines). With "CRLF" or "LF", output data contains 64-character');
  WriteLn('lines. The default is "CRLF".');
  WriteLn();
  WriteLn('--safe or -s - Encodes with "+" replaced by "-" and "/" replaced by "_" as');
  WriteLn('defined in RFC 4648 Section 5.');
  WriteLn();
  WriteLn('--decode[=<filename>] or -d [<filename>] - Decode content from base64. Omit a');
  WriteLn('file name to decode the content of standard output. See REMARKS for details');
  WriteLn('about decodable base64 input containing newlines. Enclose the filename between');
  WriteLn('" characters if it contains whitespace.');
  WriteLn();
  WriteLn('--out=<filename> or -o <filename> - Write output to the specified file. Omit');
  WriteLn('this parameter to write output to standard output (not recommended for binary');
  WriteLn('files). Enclose the filename between " characters if it contains whitespace.');
  WriteLn('You must specify --force to overwrite an existing file.');
  WriteLn();
  WriteLn('--encodestring or -E - Encode the remainder of the command line text following');
  WriteLn('two dashes (--) to Unicode (UTF16LE) base64 without newlines. The output is');
  WriteLn('suitable for use with the PowerShell -EncodedCommand parameter.');
  WriteLn();
  WriteLn('--decodestring or -D - Decode the remainder of the command line text following');
  WriteLn('two dashes (--) from base64.');
  WriteLn();
  WriteLn('--quiet or -q - Suppress any error messages written to standard error.');
  WriteLn();
  WriteLn('REMARKS');
  WriteLn();
  WriteLn('Decodable base64 input containing newlines must meet the following criteria:');
  WriteLn();
  WriteLn('* Each line''s length (except the last) must be a multiple of 4 characters');
  WriteLn('* All lines (except the last) must be the same length');
  WriteLn('* Lines cannot be longer than 996 characters');
  WriteLn('* All newlines in the file must be the same type (CRLF or LF)');
  WriteLn();
  WriteLn('If base64 input with newlines does not meet all of the above criteria, the');
  WriteLn('data will fail to decode or will produce corrupt output.');
end;

function StrToInt(const S: string; const Min, Max: Integer; out I: Integer): Boolean;
var
  N, Code: Integer;
begin
  Val(S, N, Code);
  result := (Code = 0) and (N <= Max) and  (N >= Min);
  if result then
    I := N;
end;

procedure TCommandLine.Parse();
var
  Opts: array[1..12] of TOption;
  Opt: Char;
  I: Integer;
begin
  with Opts[1] do
  begin
    Name := 'buffersize';
    Has_arg := Required_Argument;
    Flag := nil;
    Value := 'B';
  end;
  with Opts[2] do
  begin
    Name := 'decode';
    Has_arg := Optional_Argument;
    Flag := nil;
    Value := 'd';
  end;
  with Opts[3] do
  begin
    name := 'decodestring';
    Has_arg := No_Argument;
    Flag := nil;
    Value := 'D';
  end;
  with Opts[4] do
  begin
    Name := 'encode';
    Has_arg := Optional_Argument;
    Flag := nil;
    Value := 'e';
  end;
  with Opts[5] do
  begin
    Name := 'encodestring';
    Has_arg := No_Argument;
    Flag := nil;
    Value := 'E';
  end;
  with Opts[6] do
  begin
    Name := 'force';
    Has_arg := No_Argument;
    Flag := nil;
    Value := #0;
  end;
  with Opts[7] do
  begin
    Name := 'help';
    Has_arg := No_Argument;
    Flag := nil;
    Value := 'h';
  end;
  with Opts[8] do
  begin
    Name := 'newlinetype';
    Has_arg := Required_Argument;
    Flag := nil;
    Value := 'n';
  end;
  with Opts[9] do
  begin
    Name := 'out';
    Has_arg := Required_Argument;
    Flag := nil;
    Value := 'o';
  end;
  with Opts[10] do
  begin
    Name := 'quiet';
    Has_arg := Required_Argument;
    Flag := nil;
    Value := 'q';
  end;
  with Opts[11] do
  begin
    Name := 'safe';
    Has_arg := No_Argument;
    Flag := nil;
    Value := 's';
  end;
  with Opts[12] do
  begin
    Name := '';
    Has_arg := No_Argument;
    Flag := nil;
    Value := #0;
  end;
  ActionSet := [];
  Error := ERROR_SUCCESS;
  ErrorMsg := '';
  InputFileName := '';
  OutputFileName := '';
  MinBufSize := -1;
  NewlineType := base64NewlineTypeCRLF;
  UTF16Str := '';
  ForceOverwrite := false;
  Help := false;
  Quiet := false;
  Safe := false;
  OptErr := false;  // no error reporting from wgetopts
  repeat
    Opt := GetLongOpts('B:Dd::Ee::hn:o:qs', @Opts[1], I);
    case Opt of
      'B':  // --buffersize
      begin
        if StrToInt(OptArg, (BASE64_MIN_BUFFER_SIZE div 1024),
          (BASE64_MAX_BUFFER_SIZE div 1024), MinBufSize) then
        begin
          MinBufSize := MinBufSize * 1024;
        end
        else
        begin
          Error := ERROR_INVALID_PARAMETER;
          ErrorMsg := 'The --buffersize (-B) parameter requires an argument in the range '
            + IntToStr(BASE64_MIN_BUFFER_SIZE div 1024)
            + ' through '
            + IntToStr(BASE64_MAX_BUFFER_SIZE div 1024);
        end;
      end;
      'D':  // --decodestring
      begin
        Include(ActionSet, b64ActionDecodeString);
      end;
      'd':  // --decode
      begin
        Include(ActionSet, b64ActionDecode);
        InputFileName := OptArg;
      end;
      'E':  // --encodestring
      begin
        Include(ActionSet, b64ActionEncodeString);
      end;
      'e':  // --encode
      begin
        Include(ActionSet, b64ActionEncode);
        InputFileName := OptArg;
      end;
      'h':  // --help
      begin
        Help := true;
      end;
      'n':  // --newlinetype
      begin
        if SameString('CRLF', OptArg) then
          NewlineType := base64NewlineTypeCRLF
        else if SameString('LF', OptArg) then
          NewlineType := base64NewlineTypeLF
        else if SameString('None', OptArg) then
          NewlineType := base64NewlineTypeNone
        else
        begin
          ErrorMsg := 'The --newlinetype (-n) parameter''s argument must be one of: CRLF LF None';
          Error := ERROR_INVALID_PARAMETER;
        end;
      end;
      'o':  // --out
      begin
        OutputFileName := OptArg;
      end;
      'q':  // --quiet
      begin
        Quiet := true;
      end;
      's':  // --safe
      begin
        Safe := true;
      end;
      #0:
      case Opts[I].Name of
        'force':
        begin
          ForceOverwrite := true;
        end;
      end;
      '?':
      begin
        Error := ERROR_INVALID_PARAMETER;
        ErrorMsg := GetWindowsMessage(Error);
      end;
    end;
    if Error <> ERROR_SUCCESS then
      break;
  until Opt = EndOfOptions;
  if PopCnt(DWORD(ActionSet)) <> 1 then
  begin
    Error := ERROR_INVALID_PARAMETER;
    ErrorMsg := GetWindowsMessage(Error);
    exit;
  end;
  if b64ActionDecodeString in ActionSet then
  begin
    UTF16Str := ParamStr(OptInd);
    if UTF16Str = '' then
    begin
      Error := ERROR_INVALID_PARAMETER;
      ErrorMsg := 'The --decodestring (-D) parameter is missing an argument';
      exit;
    end;
  end;
  // --encodestring (-E) encodes remainder of command line after options
  if b64ActionEncodeString in ActionSet then
  begin
    UTF16Str := GetCommandTail(GetCommandLineW(), OptInd);
    if UTF16Str = '' then
    begin
      ErrorMsg := 'The --encodestring (-E) parameter is missing an argument';
      Error := ERROR_INVALID_PARAMETER;
      exit;
    end;
  end;
end;

var
  CmdLine: TCommandLine;
  B64Tool: TB64Util;
  ResultCode: DWORD;

begin
  CmdLine.Parse();

  if CmdLine.Help or (ParamCount() = 0) then
  begin
    Usage();
    exit;
  end;

  if CmdLine.Error <> ERROR_SUCCESS then
  begin
    WriteLn(StdErr, CmdLine.ErrorMsg);
    WriteLn(StdErr, 'Use --help (-h) for usage information.');
    ExitCode := Integer(CmdLine.Error);
    exit;
  end;

  B64Tool := TB64Util.Create();

  if CmdLine.InputFileName <> '' then
    B64Tool.SetInputFile(CmdLine.InputFileName);
  if B64Tool.ErrorCode = ERROR_SUCCESS then
  begin
    if CmdLine.OutputFileName <> '' then
      B64Tool.SetOutputFile(CmdLine.OutputFileName, CmdLine.ForceOverwrite);
    if B64Tool.ErrorCode = ERROR_SUCCESS then
    begin
      if CmdLine.MinBufSize <> -1 then
        B64Tool.MinBufferSize := CmdLine.MinBufSize;
      if b64ActionDecodeString in CmdLine.ActionSet then
        B64Tool.DecodeString(CmdLine.UTF16Str)
      else if b64ActionDecode in CmdLine.ActionSet then
        B64Tool.Decode()
      else if b64ActionEncodeString in CmdLine.ActionSet then
        B64Tool.EncodeString(CmdLine.UTF16Str, CmdLine.Safe)
      else if b64ActionEncode in CmdLine.ActionSet then
        B64Tool.Encode(CmdLine.NewlineType, CmdLine.Safe);
    end;
  end;

  ResultCode := B64Tool.ErrorCode;
  B64Tool.Destroy();

  if not CmdLine.Quiet then
  begin
    case ResultCode of
      ERROR_SUCCESS:      // No error
        ;
      ERROR_BROKEN_PIPE:  // Normal after piped input completes
        ResultCode := ERROR_SUCCESS;
      else
        WriteLn(StdErr, GetWindowsMessage(ResultCode, true));
    end;
  end;

  ExitCode := Integer(ResultCode);
end.
