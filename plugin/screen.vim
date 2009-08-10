" Author: Eric Van Dewoestine <ervandew@gmail.com>
" Version: 0.3
"
" Description: {{{
"   This plugin aims to simulate an embedded shell in vim by allowing you to
"   easily convert your current vim session into one running in gnu screen
"   with a split gnu screen window containing a shell, and to quickly send
"   statements/code to whatever program is running in that shell (bash,
"   python, irb, etc.).
"
"   Note: gvim is not supported. You must be running vim in a console.
"
"   Currently tested on Linux and cygwin, but should work on any unix based
"   platform where screen is supported (OSX, BSD, Solaris, etc.).  Note that
"   in my testing of cygwin, invocations of screen were significantly slower
"   and less fluid than on Linux.
"
"   Commands:
"     :ScreenShell [cmd] - Opens the split shell by doing the following:
"       1. save a session file from your currently running vim instance
"          (current tab only)
"       2. start gnu screen with vim running in it
"       3. load your saved session file
"       4. create a lower gnu screen split window and start a shell
"       5. if a command was supplied to :ScreenShell, run it
"          Ex. :ScreenShell ipython
"
"       Note: If you are already in a gnu screen session, then only steps
"             4 and 5 above will be run.
"
"     :ScreenSend - Send the visual selection or the entire buffer contents to
"                   the running gnu screen shell window.
"
"     :ScreenQuit - Save all currently modified vim buffers and quit gnu
"                   screen, returning you to your previous vim instance
"                   running outside of gnu screen
"       Note: :ScreenQuit is not available if you where already in a gnu
"             screen session when you ran :ScreenShell.
"       Note: By default, if the gnu screen session was started by
"             :ScreenShell, then exiting vim will quit the gnu screen session
"             as well (configurable via g:ScreenShellQuitOnVimExit).
"
"   An example workflow may be:
"     Open a python file to work on:
"       $ vim something.py
"
"     Decide you want to run all or pieces of the code in an interactive
"     python shell:
"       :ScreenShell python
"
"     Send code from a vim buffer to the shell:
"       :ScreenSend
"
"     Quit the screen session and return to your original vim session:
"       :ScreenQuit
"         or
"       :qa
"
"   Configuration:
"     - g:ScreenShellHeight (Default: 15): Sets the height of gnu screen
"       region used for the shell.
"     - g:ScreenShellQuitOnVimExit (Default: 1): When non-zero and the gnu
"       screen session was started by this script, the screen session will be
"       closed when vim exits.
"     - g:ScreenShellServerName (Default: 'vim'): If the gnu screen session is
"       started by this plugin, then the value of this setting will be used
"       for the servername arg of the vim instance started in the new gnu
"       screen session.
"     - g:ScreenShellExternal (Default: 0): When non-zero and not already in a
"       screen session, an external shell will be spawned instead of using a
"       split region for the shell.
"     - g:ScreenShellTerminal (Default: ''): When g:ScreenShellExternal is
"       enabled, this value will be used as the name of the terminal
"       executable to be used.  If this value is empty, a list of common
"       terminals will be tried until one is found.
"
"   Gotchas:
"     - While running vim in gnu screen, if you detach the session instead of
"       quitting, then when returning to the non-screen vim, vim will complain
"       about swap files already existing.  So try to avoid detaching.
"     - Not all vim plugins support saving state to or loading from vim
"       session files, so when running :ScreenShell some buffers may not load
"       correctly if they are backed by such a plugin.
"
" }}}
"
" License: {{{
"   Software License Agreement (BSD License)
"
"   Copyright (c) 2009
"   All rights reserved.
"
"   Redistribution and use of this software in source and binary forms, with
"   or without modification, are permitted provided that the following
"   conditions are met:
"
"   * Redistributions of source code must retain the above
"     copyright notice, this list of conditions and the
"     following disclaimer.
"
"   * Redistributions in binary form must reproduce the above
"     copyright notice, this list of conditions and the
"     following disclaimer in the documentation and/or other
"     materials provided with the distribution.
"
"   * Neither the name of Eric Van Dewoestine nor the names of its
"     contributors may be used to endorse or promote products derived from
"     this software without specific prior written permission of
"     Eric Van Dewoestine.
"
"   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
"   IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
"   THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
"   PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
"   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
"   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
"   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
"   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
"   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
"   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
"   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
" }}}

" not compatible with gvim
if has('gui_running') || !executable('screen')
  finish
endif

" Global Variables {{{

  " Sets the height of the gnu screen window used for the shell.
  if !exists('g:ScreenShellHeight')
    let g:ScreenShellHeight = 15
  endif

  " Specifies whether or not to quit gnu screen when vim is closed and the
  " screen session was started via :ScreenShell.
  if !exists('g:ScreenShellQuitOnVimExit')
    let g:ScreenShellQuitOnVimExit = 1
  endif

  " Specifies the title used for the vim screen window (<cmd> will be replaced
  " with a portion of the command supplied, if any).
  if !exists('g:ScreenShellVimTitle')
    "let g:ScreenShellVimTitle = 'ScreenShell <cmd>'
    let g:ScreenShellVimTitle = 'vim'
  endif

  " Specifies a name to be supplied to vim's --servername arg when invoked in
  " a new screen session.
  if !exists('g:ScreenShellServerName')
    let g:ScreenShellServerName = 'vim'
  endif

  " When not 0, open the spawned shell in an external window (not currently
  " supported when running in cygwin).
  if !exists('g:ScreenShellExternal')
    let g:ScreenShellExternal = 0
  endif

  " When g:ScreenShellExternal is set, this variable specifies the prefered
  " shell to use.  If not set, some common terminals will be tried.
  if !exists('g:ScreenShellTerminal')
    let g:ScreenShellTerminal = ''
  endif

" }}}

" Script Variables {{{

  let s:terminals = [
      \ 'gnome-terminal', 'konsole',
      \ 'urxvt', 'multi-aterm', 'aterm', 'mrxvt', 'rxvt',
      \ 'xterm',
    \ ]

" }}}

" Commands {{{

  if !exists(':ScreenShell')
    command -nargs=? ScreenShell :call <SID>ScreenShell('<args>')
  endif

" }}}

" Autocmds {{{

  if expand('$TERM') == 'screen'
    augroup vim_screen
      autocmd!
      autocmd VimEnter,BufWinEnter,WinEnter *
        \ exec "silent! !echo -ne '\\ek" . expand('%:t') . "\\e\\\\'"
      autocmd VimLeave * exec "silent! !echo -ne '\\ekshell\\e\\\\'"
    augroup END
  endif

" }}}

" s:ScreenShell(cmd) {{{
" Open a split shell.
function! s:ScreenShell(cmd)
  try
    if expand('$TERM') !~ '^screen'
      call s:ScreenBootstrap(a:cmd)
    else
      call s:ScreenInit(a:cmd)
    endif
  finally
    " wrapping in a try without catching anything just cleans up the vim error
    " produced by an exception thrown from one of the above functions.
  endtry
endfunction " }}}

" s:ScreenBootstrap(cmd) {{{
" Bootstrap a new screen session.
function! s:ScreenBootstrap(cmd)
  try
    let g:ScreenShell = 1
    wa
    let save_sessionoptions = &sessionoptions
    set sessionoptions+=globals
    set sessionoptions-=tabpages
    let sessionfile = tempname()
    exec 'mksession ' . sessionfile

    " support for taglist
    if exists(':TlistSessionSave') &&
     \ exists('g:TagList_title') &&
     \ bufwinnr(g:TagList_title)
      let g:ScreenShellTaglistSession = sessionfile . '.taglist'
      exec 'TlistSessionSave ' . g:ScreenShellTaglistSession
      exec 'silent! !echo "Tlist | TlistSessionLoad ' .
        \ g:ScreenShellTaglistSession . '" >> "' . sessionfile . '"'
    endif

    let bufend = bufnr('$')
    let bufnum = 1
    while bufnum <= bufend
      if bufnr(bufnum) != -1
        call setbufvar(bufnum, 'save_swapfile', getbufvar(bufnum, '&swapfile'))
        call setbufvar(bufnum, '&swapfile', 0)
      endif
      let bufnum = bufnum + 1
    endwhile

    let title = g:ScreenShellVimTitle

    " use a portion of the command in the title, if supplied
    if title =~ '<cmd>'
      let cmd = a:cmd != '' ? s:ScreenCmdName(a:cmd)[:12] : ''
      let title = substitute(title, '<cmd>', cmd, '')
    endif

    " strip leadin/trailing space and prevent an empty title.
    let title = substitute(title, '^\s\+\|\s\+$', '', '')
    if title == ''
      let title = 'ScreenShell'
    endif

    " supply a servername when starting vim if supported
    let server = ''
    if has('clientserver') && g:ScreenShellServerName != ''
      let server = '--servername "' . g:ScreenShellServerName . '" '
    endif

    exec 'silent! !screen -t "' . title . '" vim ' .
      \ server .
      \ '-c "silent source ' . sessionfile . '" ' .
      \ '-c "ScreenShell ' . a:cmd . '"'
  finally
    unlet g:ScreenShell

    " if there was an error writing files, then we didn't get far enough to
    " need this cleanup.
    if exists('save_sessionoptions')
      let &sessionoptions = save_sessionoptions
      call delete(sessionfile)

      " remove taglist session file
      if exists('g:ScreenShellTaglistSession')
        call delete(g:ScreenShellTaglistSession)
      endif

      redraw!

      let bufnum = 1
      while bufnum <= bufend
        if bufnr(bufnum) != -1
          call setbufvar(bufnum, '&swapfile', getbufvar(bufnum, 'save_swapfile'))
        endif
        let bufnum = bufnum + 1
      endwhile
    endif
  endtry
endfunction " }}}

" s:ScreenInit(cmd) {{{
" Initialize the current screen session.
function! s:ScreenInit(cmd)
  let g:ScreenShellWindow = 'shell'
  " use a portion of the command as the title, if supplied
  if a:cmd != '' && a:cmd !~ '^\s*vim\>'
    let g:ScreenShellWindow = s:ScreenCmdName(a:cmd)[:15]
  endif

  if exists('g:ScreenShell') && !exists(':ScreenQuit')
    command -nargs=0 ScreenQuit :call <SID>ScreenQuit(0)
    if g:ScreenShellQuitOnVimExit
      augroup screen_shell
        autocmd!
        autocmd VimLeave * call <SID>ScreenQuit(1)
      augroup END
    endif
  endif

  if !exists(':ScreenSend')
    command -nargs=0 -range=% ScreenSend :call <SID>ScreenSend(<line1>, <line2>)
  endif

  " use screen regions
  if !g:ScreenShellExternal || has('win32unix')
    let result = system('screen -X eval ' .
      \ '"split" ' .
      \ '"focus down" ' .
      \ '"resize ' . g:ScreenShellHeight . '" ' .
      \ '"screen -t ' . g:ScreenShellWindow . '" ')

    if !v:shell_error && a:cmd != ''
      let cmd = a:cmd . "\<c-m>"
      let result = system(
        \ 'screen -p ' . g:ScreenShellWindow . ' -X stuff "' . cmd . '"')
    endif

  " use an external terminal
  else
    let terminal = s:GetTerminal()

    let result = system('screen -X eval ' .
      \ '"screen -t ' . g:ScreenShellWindow . ' ' . a:cmd . '" ' .
      \ '"other"')

    if !v:shell_error && terminal != '' && executable(terminal)
      " gnome-terminal needs quotes around the screen call, but konsole and
      " rxvt based terms (urxvt, aterm, mrxvt, etc.) don't work properly with
      " quotes.  xterm seems content either way, so we'll treat gnome-terminal
      " as the odd ball here.
      if terminal == 'gnome-terminal'
        let result = system(terminal . ' -e "screen -x" &')
      else
        let result = system(terminal . ' -e screen -x &')
      endif
    else
      echoerr 'Unable to find a suitable terminal, please set g:ScreenShellTerminal'
    endif
  endif

  if v:shell_error
    echoerr result
  endif
endfunction " }}}

" s:ScreenSend(line1, line2) {{{
" Send lines to the screen shell.
function! s:ScreenSend(line1, line2)
  let lines = getline(a:line1, a:line2)
  let mode = visualmode(1)
  if mode != '' && line("'<") == a:line1
    if mode == "v"
      let start = col("'<") - 1
      let end = col("'>")
      let lines[0] = lines[0][start :]
      let lines[-1] = lines[-1][: end]
    elseif mode == "\<c-v>"
      let start = col("'<")
      if col("'>") < start
        let start = col("'>")
      endif
      let start = start - 1
      call map(lines, 'v:val[start :]')
    endif
  endif
  let str = join(lines, "\<c-m>") . "\<c-m>"
  let str = escape(str, '"\\')
  let result = system(
    \ 'screen -p ' . g:ScreenShellWindow .  ' -X stuff "' . str . '"')

  if v:shell_error
    echoerr result
  endif
endfunction " }}}

" s:ScreenQuit(onleave) {{{
" Quit the current screen session (short cut to manually quiting vim and
" closing all screen windows.
function! s:ScreenQuit(onleave)
  if !a:onleave
    wa
  endif
  let bufend = bufnr('$')
  let bufnum = 1
  while bufnum <= bufend
    if bufnr(bufnum) != -1
      call setbufvar(bufnum, '&swapfile', 0)
    endif
    let bufnum = bufnum + 1
  endwhile

  let result = system('screen -X quit')
  if v:shell_error
    echoerr result
  endif
endfunction " }}}

" s:ScreenCmdName(cmd) {{{
" Generate a name for the given command.
function! s:ScreenCmdName(cmd)
  let cmd = substitute(a:cmd, '^\s*\(\S\+\)\s.*', '\1', '')
  " if the command is a path to one, use the tail of the path
  if cmd =~ '/'
    let cmd = fnamemodify(cmd, ':t')
  endif
  return cmd
endfunction " }}}

" s:GetTerminal() {{{
" Generate a name for the given command.
function! s:GetTerminal()
  if g:ScreenShellTerminal == ''
    for term in s:terminals
      if executable(term)
        let g:ScreenShellTerminal = term
        break
      endif
    endfor
  endif
  return g:ScreenShellTerminal
endfunction " }}}

" vim:ft=vim:fdm=marker
