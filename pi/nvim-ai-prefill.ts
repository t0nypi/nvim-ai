/**
 * nvim-ai prefill extension.
 *
 * When pi is launched by `:AIContextContinue`, the plugin passes
 * `--nvim-ai-prefill-file <path>` with the sentence to put in the editor.
 * On startup we load that text into the core editor and remove the file, so a
 * later reload/reconnect does not paste it again.
 */
import { readFileSync, unlinkSync } from "node:fs";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const FLAG = "nvim-ai-prefill-file";

export default function (pi: ExtensionAPI) {
	pi.registerFlag(FLAG, {
		description: "File containing text to prefill in the editor (used by nvim-ai)",
		type: "string",
	});

	pi.on("session_start", async (_event, ctx) => {
		// Prefilling the editor only makes sense when a UI is attached.
		if (!ctx.hasUI) {
			return;
		}

		const value = pi.getFlag(FLAG);
		if (typeof value !== "string" || value === "") {
			return;
		}

		let text: string;
		try {
			text = readFileSync(value, "utf8");
		} catch {
			// The temp file may already be gone; nothing to prefill.
			return;
		}

		// Remove the one-shot payload so session reloads do not repeat it.
		try {
			unlinkSync(value);
		} catch {
			// Ignore races or permission issues; the text was already read.
		}

		ctx.ui.setEditorText(text.replace(/\n$/, ""));
	});
}
