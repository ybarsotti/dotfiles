// Temporary harness: renders one component with fixture data and writes the
// resulting DOM to $SHOT_DIR/$SHOT.html for shoot.sh. Delete it after use.
//
// 1. Copy this file into a scratch directory outside the repository and run
//    it from the frontend directory with the project's jest config:
//      <pm> jest --roots <scratch-dir> --modulePaths <frontend>/node_modules <file>
//    If the config rejects that root, copy it into the project's test
//    directory instead, and delete it afterwards.
// 2. Replace the import and the JSX below. Reuse the project's own render
//    helper (it usually wraps the providers) and the fixture builders of the
//    component's existing tests.
// 3. Set SHOT_DIR=/abs/out SHOT=name TZ=America/New_York on that command.
import { writeFileSync } from "node:fs";
import { render } from "@testing-library/react"; // Prefer the project's test-utils render.
// import { MyComponent } from "@/path/to/MyComponent";

it("writes the rendered DOM for a screenshot", async () => {
  render(<div>{/* <MyComponent {...fixtureProps} /> */}</div>);
  // To capture an open tooltip, menu or dialog, interact first, for example:
  // await userEvent.hover(screen.getByText("Failed attempt"));
  // await screen.findAllByRole("tooltip");
  const dir = process.env.SHOT_DIR;
  const name = process.env.SHOT ?? "shot";
  if (!dir) throw new Error("Set SHOT_DIR to an absolute output directory.");
  writeFileSync(`${dir}/${name}.html`, document.body.innerHTML);
});
