wget $(grep -hiR "m4_sv_include" ./out/ | cut -c39- | sed 's/'"'"'\])/ /') -P ./out/
