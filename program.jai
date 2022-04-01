
#program_export
start :: () {
    message := "This is a fun test, again\n";
    << cast(*string) (0x400_000 - size_of(string)) = message;

    #asm {
        int 0x80;
    }
}
