if exists('g:autoloaded_gitcommit')
    finish
endif
let g:autoloaded_gitcommit = 1

let s:PAT = '# Please enter the commit message'
let s:MAX_MESSAGES = 100
let s:FMT = '%Y-%m-%d__%H-%M-%S'
let s:CHECKSUM_FILE = $COMMIT_MESSAGES_DIR.'/checksums'

" Interface {{{1
fu! gitcommit#delete_current_message(...) abort "{{{2
    if !exists('b:msg_index')
        return
    endif
    let fname = get(glob($COMMIT_MESSAGES_DIR.'/*.txt', 0, 1), b:msg_index, '')
    if empty(fname)
        return
    endif
    let idx = b:msg_index
    " go to next message
    call gitcommit#read_last_message(+1)
    " remove previous message
    call delete(fname)
    " update checksum file
    call s:update_checksum_file(idx)
endfu

fu! gitcommit#read_last_message(...) abort "{{{2
    let messages = glob($COMMIT_MESSAGES_DIR.'/*.txt', 0, 1)
    let b:msg_index = !a:0
        \ ?     -1
        \ : !exists('b:msg_index')
        \ ?     a:1 - 1
        \ :     (b:msg_index + a:1) % len(messages)

    let msg = get(messages, b:msg_index, '')
    if filereadable(msg)
        sil! exe '1;/^'.s:PAT.'/-d_'
        if !&modifiable
            setl modifiable
        endif
        exe '0r '.msg
        call append("']", '')
        " need to write,  otherwise if we just execute `:x`,  git doesn't commit
        " because, for some reason, it thinks we didn't write anything
        sil w
    endif
endfu

fu! gitcommit#save_next_message(when) abort "{{{2
    if a:when is# 'on_bufwinleave'
        augroup my_commit_msg_save
            au! * <buffer>
            au BufWinLeave <buffer> call gitcommit#save_next_message('now')
        augroup END
    else
        let last_line = search('^.*\S.*\%(\s*\n\)*'.s:PAT)
        if last_line
            let msg = getline(1, last_line)
            let md5 = s:get_md5(msg)
            let idx = match(readfile(s:CHECKSUM_FILE), md5)
            " save the message in a file if it has never been saved
            if !filereadable(s:CHECKSUM_FILE) || idx == -1
            "  │                               │{{{
            "  │                               └ there's already a file storing this message
            "  └ there's no checksums file
            "}}}
                call s:write(msg, md5)
            " if the message has already been saved, refreshing the timestamp in
            " its filename, so  that next time I commit,  it's immediately used,
            " and I don't have to look for it in the history
            elseif filereadable(s:CHECKSUM_FILE) && idx != -1
                let new_filepath = s:refresh_message_timestamp(idx)
                call s:update_checksum_file(idx, md5, new_filepath)
            endif
        endif
        sil! au! my_commit_msg_save * <buffer>
        call s:maybe_remove_oldest()
    endif
endfu

" }}}1
" Core {{{1
fu! s:maybe_remove_oldest() abort "{{{2
    let messages = glob($COMMIT_MESSAGES_DIR.'/*.txt', 0, 1)
    if len(messages) > s:MAX_MESSAGES
        let oldest = messages[0]
        call delete(oldest)
    endif
endfu

fu! s:refresh_message_timestamp(idx) abort "{{{2
    let old_filename = matchstr(readfile(s:CHECKSUM_FILE)[a:idx], '\s\+\zs.*')
    let old_filepath = $COMMIT_MESSAGES_DIR . '/' . old_filename
    let new_filepath = $COMMIT_MESSAGES_DIR . '/' . strftime(s:FMT).'.txt'
    call rename(old_filepath, new_filepath)
    return new_filepath
endfu

fu! s:update_checksum_file(idx, ...) abort "{{{2
    let new_checksums = readfile(s:CHECKSUM_FILE)
    call remove(new_checksums, a:idx)
    if a:0
        let [md5, new_filepath] = a:000
        call add(new_checksums, md5 . '  ' . substitute(new_filepath, '.*/', '', ''))
    endif
    call writefile(new_checksums, s:CHECKSUM_FILE)
endfu

fu! s:write(msg, md5) abort "{{{2
    " we need the seconds in the file title to avoid overwriting a message
    " if we make 2 commits in less than a minute
    let file = $COMMIT_MESSAGES_DIR.'/'.strftime(s:FMT).'.txt'
    call writefile(a:msg, file)
    call writefile([a:md5.'  '.fnamemodify(file, ':t')],
        \ s:CHECKSUM_FILE, 'a')
endfu

" }}}1
" Utility {{{1
fu! s:get_md5(msg) abort "{{{2
    sil let md5 = system('md5sum <<< '.string(join(a:msg, "\n")))
    let md5 = matchstr(md5, '[a-f0-9]*')
    return md5
endfu

