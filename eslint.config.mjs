export default [
	{
		ignores: ["node_modules/**"]
	},
	{
		files: ["luci-app-easytier/htdocs/**/*.js"],
		languageOptions: {
			ecmaVersion: "latest",
			sourceType: "script",
			parserOptions: {
				ecmaFeatures: {
					globalReturn: true
				}
			},
			globals: {
				baseclass: "readonly",
				document: "readonly",
				_: "readonly",
				E: "readonly",
				easytier: "readonly",
				FormData: "readonly",
				L: "readonly",
				dom: "readonly",
				form: "readonly",
				fs: "readonly",
				network: "readonly",
				navigator: "readonly",
				poll: "readonly",
				rpc: "readonly",
				XMLHttpRequest: "readonly",
				ui: "readonly",
				uci: "readonly",
				validation: "readonly",
				view: "readonly",
				window: "readonly"
			}
		},
			rules: {
			"constructor-super": "error",
			"no-async-promise-executor": "error",
			"no-cond-assign": "error",
			"no-constant-binary-expression": "error",
			"no-dupe-args": "error",
			"no-dupe-keys": "error",
			"no-duplicate-case": "error",
			"no-ex-assign": "error",
			"no-fallthrough": "error",
			"no-func-assign": "error",
			"no-import-assign": "error",
			"no-irregular-whitespace": "error",
			"no-loss-of-precision": "error",
			"no-new-native-nonconstructor": "error",
			"no-undef": "error",
			"no-promise-executor-return": "error",
			"no-self-assign": "error",
			"no-sparse-arrays": "error",
			"no-unexpected-multiline": "error",
			"no-unreachable": "error",
			"no-unsafe-finally": "error",
			"no-unsafe-negation": "error",
			"no-unsafe-optional-chaining": "error",
			"no-unused-vars": ["error", { args: "none", caughtErrors: "none" }],
			"no-useless-backreference": "error",
			"use-isnan": "error",
			"valid-typeof": "error"
		}
	}
];
