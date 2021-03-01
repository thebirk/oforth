package forth

import "core:os"
import "core:fmt"
import "core:unicode"
import "core:strconv"
import "core:runtime"
import scan "core:text/scanner"

Stack_Value :: union {
    int,
    Word,
}

Mode :: enum {
    Interpret,
    Compile
}
State :: struct {
    dict: [dynamic]Word,
    stack: [dynamic]Stack_Value,
    scanner: scan.Scanner,
    mode: Mode,
    active_word: ^Word,
}

Code_Value :: union {
    proc(state: ^State),
    ^Word,
    int
}
Word :: struct {
    name: string,
    is_immediate: bool,
    code: [dynamic]Code_Value,
}

builtin_colon :: proc(state: ^State) {
    state.mode = .Compile;
}

builtin_semicolon :: proc(state: ^State) {
    if state.mode != .Compile do panic("; before :");
    state.mode = .Interpret;
}

builtin_dot :: proc(state: ^State) {
    v := pop(state);
    fmt.print(v);
}

builtin_dup :: proc(state: ^State) {
    v := peek(state);
    push(state, v);
}

builtin_cr :: proc(state: ^State) {
    fmt.println();
}

builtin_add :: proc(state: ^State) {
    b := pop(state).(int);
    a := pop(state).(int);
    push(state, a + b);
}

builtin_sub :: proc(state: ^State) {
    b := pop(state).(int);
    a := pop(state).(int);
    push(state, a - b);
}

builtin_mul :: proc(state: ^State) {
    b := pop(state).(int);
    a := pop(state).(int);
    push(state, a * b);
}

builtin_div :: proc(state: ^State) {
    b := pop(state).(int);
    a := pop(state).(int);
    push(state, a / b);
}

push :: proc(state: ^State, v: Stack_Value) {
    append(&state.stack, v);
}

pop :: proc(state: ^State)  -> Stack_Value {
    return runtime.pop(&state.stack);
}

peek :: proc(state: ^State) -> Stack_Value {
    return state.stack[len(state.stack)-1];
}

init :: proc(state: ^State, file: string) {
    state.mode = .Interpret;

    src, _ := os.read_entire_file(file);
    scan.init(&state.scanner, string(src));
    state.scanner.flags = {.Scan_Idents, .Scan_Ints, .Scan_Floats, .Scan_Chars, .Scan_Strings, .Scan_Comments, .Skip_Comments};
    state.scanner.is_ident_rune = proc(ch: rune, i: int) -> bool {
        if unicode.is_digit(ch) && i == 0 do return false;
        return ch != ' ' && ch != '\n' && ch != scan.EOF;
    };

    append(&state.dict, Word{name=":", code={builtin_colon}});
    append(&state.dict, Word{name=";", code={builtin_semicolon}});

    // : . ( x -- )
    append(&state.dict, Word{ name=".", code={builtin_dot} });

    // : dup ( x -- x x )
    append(&state.dict, Word{ name="dup", code={builtin_dup} });

    // : .d ( x -- x )
    append(&state.dict, Word{ name=".d", code={builtin_dup, builtin_dot} });

    // : cr ( -- )
    append(&state.dict, Word{ name="cr", code={builtin_cr} });

    // : + ( a b -- a+b )
    append(&state.dict, Word{ name="+", code={builtin_add} });
    // : - ( a b -- a-b )
    append(&state.dict, Word{ name="-", code={builtin_sub} });
    // : * ( a b -- a*b )
    append(&state.dict, Word{ name="*", code={builtin_mul} });
    // : / ( a b -- a/b )
    append(&state.dict, Word{ name="/", code={builtin_div} });
}

read_word :: proc(state: ^State) -> union{int, string} {
    tok := scan.scan(&state.scanner);
    if tok == scan.EOF do return nil;
    
    text := scan.token_text(&state.scanner);
    switch tok {
    case scan.Int:
        v, _ := strconv.parse_int(text);
        return v;
    case:
        return text;
    }
}

find_word :: proc(state: ^State, name: string) -> ^Word {
    // Iterate backwards to allow overriding of words
    start := state.active_word != nil
                ? len(state.dict) - 2
                : len(state.dict) - 1;
    for i := start; i >= 0; i -= 1 {
        word := &state.dict[i];

        if word.name == name {
            return word;
        }
    }

    return nil;
}

exec_word :: proc(state: ^State, word: ^Word) {
    for c in word.code {
        switch kind in c {
        case proc(state: ^State):
            kind(state);
        case ^Word:
            exec_word(state, kind);
        case int:
            push(state, kind);
        }
    }
}

main :: proc() {
    state: State;
    init(&state, "demo.forth");

    DEBUG :: false;

    word := read_word(&state);
    for word != nil {
        when DEBUG do fmt.println(word);

        if state.mode == .Compile {
            if state.active_word != nil {
                // add code
                when DEBUG do fmt.println("add code");

                switch kind in word {
                case string:
                    if kind == ";" {
                        builtin_semicolon(&state);
                        word = read_word(&state);
                        continue;
                    }

                    w := find_word(&state, kind);
                    if w == nil {
                        fmt.panicf("unknown word '%v'", kind);
                    }

                    if w.is_immediate {
                        exec_word(&state, w);
                    } else {
                        append(&state.active_word.code, Code_Value(w));
                    }
                case int:
                    append(&state.active_word.code, Code_Value(kind));
                }

                word = read_word(&state);
                continue;
            } else {
                // start new word
                when DEBUG do fmt.println("start new word");
                append(&state.dict, Word{name=word.(string)});
                state.active_word = &state.dict[len(state.dict)-1];

                word = read_word(&state);

                if w, ok := word.(string); ok {
                    if w == "immediate" {
                        state.active_word.is_immediate = true;
                        word = read_word(&state);
                    }
                }
                continue;
            }
        } else {
            if state.active_word != nil {
                // finish word
                when DEBUG do fmt.println("finish word");
                state.active_word = nil;
                // complain about missing then?
            }
        }

        switch kind in word {
        case string:
            w := find_word(&state, kind);
            if w == nil {
                panic("unknown word");
            }
            exec_word(&state, w);
        case int:
            push(&state, kind);
        }

        when DEBUG do fmt.println("stack:", state.stack);
        word = read_word(&state);
    }
}
