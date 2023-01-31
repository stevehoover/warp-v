# Edalize script to build warp-v
# python edalize_warpv.py
from edalize import *
import os
work_root = 'build_multifile'

files = [
    {'name':os.path.relpath('warp-v.tlv',work_root),'file_type':'TLVerilogSource'}
]

tool_options = {
		"sandpipersaas": {                  # Any arguments that needed to be passed to sandpiper-saas
			"sandpiper_saas": [
				"--bestsv", "--inlineGen", "--m4def 'm5_CONFIG_EXPR=m5_def(STANDARD_CONFIG,4-stage)'"
			],
            "output_file":"warp-v_rtl.sv", # One file name that ends with .v or .sv
            "output_dir":"out1"  #,           # Optional
            # "sandpiper_jar":" <Arguments to the sandpiper compiler>",
            # "endpoint":"<Optional: URL for the compile service endpoint",
            # "includes" :"List of include files to be used durung compilation "
		}
	}
tool = 'sandpipersaas'
parameters = {}
edam = {
    'files':files,
    'name':'build_tlv1',
    'parameters':parameters,
    'tool_options':tool_options
}

backend = get_edatool(tool)(edam=edam, work_root=work_root)

os.makedirs(work_root)
backend.configure()
backend.build()
backend.run()
