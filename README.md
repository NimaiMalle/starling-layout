# Layout System

A data driven system for instantiating and arranging [Starling](http://gamua.com/starling/) display objects and [Feathers](http://feathersui.com/) controls.

## Layout JSON File Structure

The JSON files declare a 

controls | An array of object data used to instantiate display objects.
:-------- | :--------
styles | A dictionary of "styles" that can be referenced by controls.
extends | A reference to another layout file that this file will extend.
overrides | A dictionary of ids from the layout being extended, containing fields will be overridden.
data | An array of arbitrary typed object definitions accessible by id from.
assets | A list of named assets to be loaded for this layout.  (See assets section)


## The "controls" Section

The "controls" are an array of display object definitions to instantiate.  The fields of each control definition depend on the type of object being defined.  All display objects share many basic fields like “x” and “y”, but some are specific, like “label” for the Feathers Button class.

#### Standard Fields For "controls"

id | An optional id for this control.  Allows you to get at the instance from code, to attach a listener, set text, or other changes that happen at run time.  If supplied, the id must be unique across the entire layout file unless it's conditionally included using the "includeInLayout" field (See Conditional Layouts and Duplicate ids)
_type | The fully qualified class name for this control.  For example, "starling.display.Quad"
style | An optional reference to a style.  (See The “styles” Section)
overrides | An optional section of control ids declared in the style, and the fields that will be overridden.
x, y, width, height | etc., etc., - all the public fields from Starling DisplayObject.
children | An array of more controls to be added as children of this control.
layer | The name of a layer, from our Layer system (more documentation needed)
group | To create an grouping of controls accessible by name and sequential index.  For example, if you have a bunch of coin images, you can put them all in
  "group": "coin"
Controls within a group can access their groupIndex in equations, for example:
  "rotation": "(this.groupIndex*-0.1963495409)"
includeInLayout | Specifies whether or not this control is instantiated at all when creating controls for a view.  This would be used in conjunction with layout variants.  (See Layout Variants)
delayLayout | Delay the creation and layout of a control and all it's children indefinitely, or for a certain number of frames.  (See Delaying Layout for Performance)


**Magic Fields For "controls"**

Aside from the standard fields above and the fields from the _type’s class structure, there are "magic" fields used by the layout engine.  (See ViewLayout.as for implementation)

repeat | Create multiple copies of this control.  (See repeating controls)
scale | Set both scaleX and scaleY to the same value.  The value can be a decimal number, or a percentage string such as "90%".  If a percentage is specified, the scale will be set so that the resulting size is the given percentage of the parents dimensions.  Width or height will be set depending on which is larger.
depth | Change the visual sorting order of a control.  Controls with greater values for "depth" will appear above those with lesser values.  By default, depth will always be one more than the previous control.  Also by default, the first control's depth is zero.
pivot | Set both pivotX and pivotY to the same value.
horizontalCenter, verticalCenter | Position your center relative to your parent’s center.  Use 0 (zero) for dead-center, or add or subtract using any other value
right | Position your right edge relative to your parent’s right edge.  Use positive numbers will move the control towards the center of the parent, negative numbers move outside, beyond the right edge of the parent.
bottom | Position your bottom edge relative to your parent’s bottom edge.  Use positive numbers will move the control up towards the center of the parent, negative numbers move down, beyond the bottom of the parent.
left, top | Same as x, y, I think.
textureId | Use a texture from the resource manager.  Can be an absolute path or a texture ID from a texture atlas.  For Buttons, it will automatically try to assign default, hover, and disabled variations.
debug | Add a debug rectangle around any control in your layout json by adding the "debug" magic field and a color value, like "0xFF0000" for red.
Debug rectangles only show up in debug builds.
iconScale | For buttons, set icon scaleX and scaleY.


#### Special Case for "top", “bottom”, “left”, and “right”

As stated above, these magic fields are used to calculate an x and y position based on the parent.  It should be noted that you can set both "left" and “right”, and the layout engine will calculate an x position and a width.  Of course, the same is true for “top” and “bottom”.  You can also set an “x” and a “right” and to set position and a width, and/or “y” and “bottom” to set position and height.

### Using Percentages

For most fields dealing with widths and heights, you can specify the value as a percentage.  This will use the parents dimensions to calculate your value.  For example:

	"width": "75%"

Values set this way will not maintain a connection, like Binding in Flex.  It will merely set the value once on initialization.  When used on controls at the root level, the dimensions of the stage will be used.

Percentages can also be used when setting "x" and “y”, in cases where that’s useful.

### Using Context Variable String Substitution

String values can be parameterized by referencing context variables in curly braces inside of the string.

	"fontId": "images2/SlotThemes/**{theme}**/WABitMap.jxr"

### Referencing Other Controls

You can set the field of one control to equal the value of a field in another.  Use the form "{id.field"} to read the value from another control’s field.  For example, this will use the value of x from a control with id "foo":

	"x": "{foo.x}"

#### Caveats

* Values set this way will not maintain a connection, like Binding in Flex.  It will merely set the value once on initialization, so it’s really only useful in static layouts.

* Controls in the layout data are processed in the order they are declared, so it is not reliable to reference a control that is declared *above*.  If the value is a constant, this will work fine, but not for values that are computed during the positioning phase of layout.

* You can reference some magic fields of other controls, even though the Starling or Feathers classes do not declare these fields.  This includes: "scale", "pivot", "top", "bottom", "left", and "right".

### Using Mathematical Expressions

Values can use mathematical expressions using string values enclosed in parenthesis, for example:

	"x": "(foo.x*2)"

The expressions can reference other control's values, and use any constant or function declared in Flash's Math package.  For example:

	"x": "(foo.x+(random()-0.5)*10)"

### Referencing variables in the View Context

In addition to fields of other controls, mathematical expressions can also use variables that live in the View Context.

The View Context is a collection of name-value pairs.  Entries are added by ActionScript code, or by calling the setContext function of an [AnimatedDisplayObjectContainer](#heading=h.xfmomrly5vvy) in one of it's animations.  (For slot games, all of the values declared in the slot machine spec are added to the View Context, as well as the theme name.)

*An example of View Context variable use can be found in the Jungle Jamboree Layout json file, where two view context variables, pearlAnimationCount and pearlCount are used to control the visibility of the free spin collection items.*

The Dialog Viewer has a **Context Explorer** window where you can view all of the current view context variables.

### Expressions in Typed and Untyped Data

Most of the data in a view layout file is strongly typed.  Controls like Buttons, LayoutGroups, etc. declare a specific class ("_type").  In those cases, the data is being assigned to fields with known types.  If a String is being assigned to a numeric field, the String is evaluated as an expression.  For String to String assignments, context substitutions in curly braces are processed.  But for untyped data, like "params" in tween definitions, or the [TextFormat](http://help.adobe.com/en_US/FlashPlatform/reference/actionscript/3/flash/text/TextFormat.html) ActionScript class which has fields that are all Objects, it's not possible to detect when a String is being assigned to a number, since the field is untyped.  In those cases, Strings are never evaluated.  Sometimes this is desired, sometimes now.  However you can force a String to evaluate by putting an exclamation point in front of the leading parenthesis.

**Example (for untyped data only):**

This expression in tween data params will not be evaluated when parsed, and will remain a String.

	"pearlAnimationCount": "(pearlAnimationCount + 1)" }

Adding an exclamation point before the open parenthesis will force the expression to be evaluated and the resulting value being used.

	"pearlAnimationCount": "!(pearlAnimationCount + 1)" }

### View Context Data Binding

If a mathematical expression references a view context variable, and you want that expression re-evaluated any time the view context variable changes, you can add an @ sign in front of the first parenthesis.  For example:

	"height": "@(50*foo)",

Borrowing the syntax from Flex for two-way binding (since we need *some* new syntax, even though this is strictly one-way), the above example would set up a binding between the control's "height" and a context variable value named "foo".  Every time "foo" changed, this would be re-evaluated and assigned to height. 

### Specifying "depth"

The ability to specify the visual sort order of controls using "depth" was added in order to separate the order that controls are declared from the order that they're displayed.  This really only matters if you want to reference controls that would normally come after you in the control list.

For example, we have coins splashed around the edges of many of our dialogs.  It's desirable to position the coins relative to the dialog frame, but we want the coins to sort behind it.  By default, to get the coins behind the dialog, we'd declare them earlier in the list of controls.  But the coins can't reference the dialog's width or position, since we process controls in the order they're declared.  With "depth", we can move the coins to the end of the control list, after the dialog has been sized and positioned, but still sort them visually below using "depth": -1.

### Repeating Controls

Any control can be repeated an arbitrary number of times in the layout by specifying a "repeat" property.  The value of the property may be a literal or an expression referencing context variables, the ActionScript Math package, and other features of [expressions](#heading=h.s8bxc59hmcru).  Repeated controls can be nested.  You may use the groupIndex property inside of any expression to access your current index.  You can build texture ids using a base name and append the groupIndex to reference different textures for each repeated instance.

#### Example:

	{
	  "_type": "ui.controls.LayoutGroup",
	  "direction": "horizontal",
	  "gap": 2,
	  "children": [
	    {
	      "_type": "ui.controls.LayoutGroup",
	      "direction": "vertical",
	      "gap": 2,
	      "repeat": 3,
	      "children": [
	        {
	          "_type": "ui.controls.BCGQuad",
	          "width": 8,
	          "height": 8,
	          "repeat": 3,
	          "rotation": "(0.05***groupIndex**)",
	          "pivot": 0.5,
	          "group": "quads"
	        }
	      ]
	    }
	  ]
	}
![repeat example](http://imageshack.com/a/img924/4595/UZ8C1j.png)

### Native Text Effects

Filters and gradients can be applied to Label and LocLabel text.  To do so, add a "nativeFilters" array to the "textRendererProperties" section of the label data.

The "nativeFilters" array can contain any of the following:

* Flash BitmapFilter classes (see Adobe documentation [here](http://help.adobe.com/en_US/FlashPlatform/reference/actionscript/3/flash/filters/BitmapFilter.html))
* A gradient definition of type ui.controls.support.Gradient (see Adobe documentation [here](http://help.adobe.com/en_US/FlashPlatform/reference/actionscript/3/flash/display/Graphics.html#beginGradientFill()))
    * fillType "linear" or "radial", default "linear"
    * colors an array of color values
    * alphas an array of alpha values
    * ratios an array of "ratios" for the color and alpha entries
    * rotation defaults to pi/2
* An explicit null - will render plain text
* An Object containing one or more of:
    * color a 32 bit color, optionally including alpha in the high byte
    * blendMode "add", "alpha", "darken", "difference", "erase", "hardlight", "invert", "layer", "lighten", "multiply", "normal", "overlay", "screen", "shader", "subtract"
    * alpha 0.0 to 1.0

Filters will be applied to the ext in the order they appear in the "nativeFilters" array.

Any time an entry that is not a Filter (like a gradient or Object) is encountered, the text will be rendered using the filters up to that point.  WIth this, you can create layered text effects.

For example:

	  "nativeFilters": [
	    {
	      "_type": "flash.filters.GlowFilter",
	      "color": "0xFFFFFF",
	      "quality": 2,
	      "blurX": 8.0,  "blurY": 8.0,
	      "strength": 128
	    },
	    {
	      "_type": "ui.controls.support.Gradient",
	      "colors": ["0x290a59","0xff7c00"]
	    },
	    {
	      "_type": "flash.filters.DropShadowFilter",
	      "distance": 8.0,
	      "alpha": 0.5,
	      "blurX": 8.0,  "blurY": 8.0
	    },
	    {
	      "color": "0x80FFFF00",
	      "blendMode": "add"
	    },
	    {
	      "_type": "flash.filters.GlowFilter",
	      "color": "0xFFFFFF",
	      "inner": true,
	      "quality": 2,
	      "blurX": 2.0,  "blurY": 2.0,
	      "strength": 128
	    }
	  ],
	...

Renders this:

![image alt Alert](http://imageshack.com/a/img923/6121/VsoQXI.png)

### Conditional Layouts and Duplicate ids

Sometimes a control or group of controls needs a completely different layout in one layout variant vs. another.  (Also see [Layout Variants](#heading=h.cf0w7lu00nu3)).  This can easily happen between a phone layout and a web layout, for example.  In these cases, it's convenient to use the same "id" for a button even though it might appear in as a child in a different section of the layout hierarchy.  To accommodate this,  use the "includeInLayout" field inside your control along with a variant.

For example, the following JSON declares two controls that are both using the id "playButton", but since they have mutually exclusive "includeInLayout" settings, the client will only create one of them.

	{
		"_type": "ui.controls.BCGButton",
			"includeInLayout.mobile": false,
			"includeInLayout.web": true,
			"id": "playButton",
			…
	},
	{
			"_type": "ui.controls.BCGImage",
			"includeInLayout.mobile": true,
			"includeInLayout.web": false,
			"id": "playButton",
			…
	}

### Layout Groups

_(The Layout Groups discussed here predate Feather's native Layout Groups.  Newer code should ignore this and use the Feather's classes.)_

The LayoutGroup class can be a simple container, or a powerful layout manager.  The LayoutGroup has the following interesting fields:

Property | Description
:-------- | :--------
direction | Which way to layout the children: "vertical", "horizontal", or "none".  The default is "none".
gap | How much space to put between each child.  Negative values can be used to make children overlap.  (If you need more space between particular children, add a spacer Quad, alpha 0.) |
horizontalAlign verticalAlign | This controls how the children are aligned: “left”, “center”, “right”, “flush”, "flat", or “none”. |

A value of “flush” will ignore any specified “gap” value and evenly distribute the children.

A value of “flat” will ignore any specified “gap” value and evenly distribute the children, plus a half-gap at each end.

The default is “left” or "top" respectively.
reverse | Position the children starting with the last child first.  Useful if using a negative gap, and not getting the right overlap sorting.
paddingTop, paddingBottom, paddingLeft, paddingRight | Adjust how far in from the edges of the group are the children positioned.  Only applies "horizontal" or "vertical" layout groups.
skipInvisible | Does not allocate space for items that are marked “visible: false”


The BCGList is the base class for BCGHorizontalList and BCGVerticalList classes.  BCGList provide the shared properties that both child classes use.

Property | Description
:-------- | :--------
itemRendererTypeName | The class type name of the item renderer to be used for displaying the contents of the list.  This must be set before adding data to the list.
itemWidth | The width of the item renderer.
itemHeight | The height of the item renderer.
gap | The gap between each item renderer in the list.
listPaddingTop | The padding between the top of the item renderer and the top padding of the list.
listPaddingRight | The padding between the right of the item renderer and the right padding of the list.
listPaddingBottom | The padding between the bottom of the item renderer and the bottom padding of the list.
listPaddingLeft | The padding between the left of the item renderer and the left padding of the list.
pageDirection | The direction of the paging of the list.  This is set internally by the child list classes but can be overridden by setting this property to either "vertical" or “horizontal”.
scrollTweenDuration | The number of seconds the tween will take to scroll to the next item in the list when paging.
itemsPerPage | The number of items on a page that are shown at one time on the list.  Setting this property will auto size the list to fix all of the items on the page unless an explicit width and height are set.


BCGHorizontalList and BCGVerticalList classes provide their own properties that are not derived the BCGList base class.  Both of these classes contain an internal layout class that defines the layout of the list item renderers.

Property | Description
:-------- | :--------
hasVariableItemDimensions | When the layout is virtualized, and this value is true, the items may have variable width values.
verticalAlign | If the total item height is less than the bounds, the positions of the items can be aligned vertically.
horizontalAlign | The alignment of the items horizontally, on the x-axis.
scrollPositionHorizontalAlign | (BCGHorizontalList Property Only) When the scroll position is calculated for an item, an attempt will be made to align the item to this position.
scrollPositionVerticalAlign | (BCGVerticalList Property Only) When the scroll position is calculated for an item, an attempt will be made to align the item to this position.


## Animated Display Object Container

An AnimatedDisplayObjectContainer has a "children" array of controls, plus an "animation" map of names to Greensock timelines.

Animations must declare a "target", specifying the control that will be acted on.  The "target" field can specify the name of any child control, the value "this", or an "id" or "group" of an unrelated control.

An entry in the "animation" map may optionally list a "when" clause.  The expression in the "when" may either reference a view context variable, or be the name of a control plus ".touch".  When the referenced control is touched (clicked) or when any context variables in the expression change, the animation will play.

Animations must declare a **"tweenType"** or a **"function".**

### Tweens

For animation entried that declare a "tweenType", the value can be one of the following:

* "com.greensock.TimelineLite"
* "com.greensock.TimelineMax"
* "com.greensock.TweenLite"
* "com.greensock.TweenMax"

The Timeline types must have a **"tweens"** array which can contain more tween declarations.

The "target" field must be one of the following:

* "this" - target the AnimatedDisplayObjectContainer instance itslef
* "parent" - target this AnimatedDisplayObjectContainer instance's parent control
* "view" - target the view (parent extending BaseView)  that contains this control
* The name of a child.  (Recall that "name" can be different from "id")
* The id of any control in the view
* The id of any instance declared in the "data" section
* A group name with an index in square brackets, i.e. "coin[2]"
* A group name alone - all controls in the group will be targeted

### Functions

For animation entries that declare a "function", the value can be any function that can be called on the "target".

Passing Parameters to Functions

A "params" array lets you pass arguments to the function (including expressions).  Expressions are evaluated at the time the function is invoked on the timeline.  To cause expressions in the "params" list for the function to be evaluated at the time the animation is *played*, add "earlyEval": true to your animation entry.  This is necessary if you want to start playing multiple animations and change a context variable between each play.  Without "earlyEval", the params won't be evaluated until at least the next frame when the function is actually called.

##### Animated Display Object Container Functions

When using "this" for target, you can call functions on the Animated Display Object Container itself, like:

* **play** - tell another control to play an animation or emit particles
* **stop** - tell another control to stop animating or emitting
* **move** - instantly move one control to the position of another
* **arcTo**, **arcFrom** - make a control follow a curved path from where it is to another control
* **setContext** - set one or more view context variables
* **modifyControl** - copy fields from a "properties" parameter onto another control
* **broadcastContext** - causes any "when" clauses referencing the context variable to trigger

For more information on these functions, check the source code in AnimatedDisplayObjectContainer.as.

#### Example

	"BonusHorus": {
		"_type": "ui.controls.AnimatedDisplayObjectContainer",
		"children": [
			{
				"_type": "ui.controls.BCGImage",
				"name": "symbol",
				"textureId": "Symbols/BonusHorus"
			}
		],
		"processManagerName": "SlotsWindow",
		"animation": {
			"pop": {
				"tweenType": "com.greensock.TweenMax",
				"repeat": 1,
				"yoyo": true,
				"target": "parent",
				"duration": 0.125,
				"to": { "scaleX": 1.3, "scaleY": 1.3 },
				"ease": "Linear.easeNone"
			},
			"foo": {
				"tweenType": "com.greensock.TweenLite",
				"target": "symbol",
				"duration": 1,
				"x": "20",
				"ease": "Expo.easeInOut"
			}
		}
	}

## The "styles" Section

The "styles" section of the layout JSON file is used to specify named blocks of data which other controls can use as a starting point, and override as needed.  Styles are perfect for blocks of formatting that are repeated even once in your layout.  For example:

	"styles": {
		"greenButton": {
			"height": 50,
			"horizontalAlign": "center",
			"textureId": "Common/GeneralButton_Green",
			"width": 170
		}
	}
	...
	"controls": [
		{
			"_type": "ui.controls.BCGButton",
			"id": "okButton",
			"style": "greenButton"
		}
		...
	]

The fields from the style are used first, then the fields declared in the control are overlaid.  Styles can reference other styles, as well.

### Styles as Templates

You can declare typed, nested controls in a style.  When referencing such a style, you can have an "overrides" section that targets specific controls in the style and sets their fields.  For example:

	"styles": {
		"foo": {
			"_type": "ui.controls.LayoutGroup",
			"direction": "vertical",
			"children": [
				{
					"_type": "starling.display.Quad",
					"id": "quad1",
					"style": "bar"
				},
				{
					"_type": "starling.display.Quad",
					"id": "quad2",
					"style": "bar"
				}
			]
		}
	}
	...
	"controls": [
		{
			"style": "foo",
			"direction": "horizontal",
			"overrides": {
				"quad1": {
					"color": "0xFF0000"
				},
				"quad2": {
					"color": "0x00FF00"
				}
			}
		}
		...
	]

The above results in two quads, stacked horizontally, one red one green.  Note that immediate values of the style can be overridden by simply re-declaring the key-value, but values nested more deeply as children must have a unique id that you can reference in the "overrides" section if you want to set their value.

### Styles extending other styles

Styles can declare "style" properties as well, and extend other styles.  The same rules apply as above.  You can re-declare any property to override it, and you can use an "overrides" section to change values in children controls.

### Style id properties

When declaring a control with a style, controls within that style that declare an "id" will get their "id" uniquified by prepending the id of the control.

	"styles": {
		"foo": {
			"_type": "starling.display.Quad",
			"id": "quad",
			"width": 20,
			"height": 20
		}
	},
	"controls": [
		{.
			"style": "foo",
			"id": "controlA"
		},
		{
			"style": "foo",
			"id": "controlB"
		}
	]

In the above example, the id of the two quads become:

* controlA/quad
* controlB/quad

### Context and Text Substitution in Styles

Styles can be parameterized using text substitution variables.  For example, a style could have a textureId property declared as "images2/{name}.jxr".

	"styles": {
		"foo": {
			"_type": "ui.controls.BCGImage",
			"textureId": "images2/**{name}**.jxr"
		}
	},
	"controls": [
		{
			"style": "foo",
			"context": {
				"name": "pictureA"
			}
		},
		{
			"style": "foo",
			"context": {
				"name": "pictureB"
			}
		}
	]

## The "extends" Section

Layout files can import and extend other layout files.   To make use of this, at the root level of your layout JSON, add an "extends" string field or array.  When your layout is processed, first all of the data referenced is overlayed and whatever you declare overlays that.

### Styles in Extended Layouts

It may be helpful to consolidate common styles into a single file that is added to the "extends" sections of your other layout files.

### Controls in Extended Layouts

If the layout you’re extending has "controls", you must add an “overrides” section to change anything about the controls.  Overrides are a map of control ids to fields that you wish to set.

Using overrides, you can have another layout define the structure of your controls.  You can change existing fields, or add new children and add complex content.

For example, a DialogLayout JSON file could provide a frame, decorations, a close button and an empty layout group with the id "content".  You could extend that file and override the“content” control to add a “children” array.

## Layout Variants

Multiple values for any field in a control or style can be supplied by adding a dot and a variant name.  For example:

		"scale": 0.75,
		"scale.web": 0.5,
		...

The **ViewLayout** class has a static variable LAYOUT_VARIANT which can be set to null to use no variants, or to any String value to make fields with that suffix take priority.  Technically, the system allows for multiple active variants at once, but the current ViewLayout interface only lets you have one active at a time, or none.

## Layout Performance

The time it takes to render your layout, and the amount of video memory it uses are critical metrics.  The "Dialog Viewer" tool lets you monitor key performance metrics.  And, there are tools at your disposal to increase the performance of your views and dialogs.

### Dialog Viewer

In the Dialog Viewer, the status bar (at the bottom of the window) and the "stats" view overlaying your dialog on the top-left are your first line of defense against poor performance.

#### Status Bar

The status bar is on the bottom of the main window of the Dialog Viewer.  It lets you know how much memory, video memory (in megapixels), and time (in milliseconds) it takes to show your view.

![image alt text](http://imageshack.com/a/img921/723/ZLzLUn.png)

What the acceptable thresholds are here are subjective.  They change as our expectations change for what is base-line change.  Layout time is going to be unique to your machine, and whatever else you have running at the time.  However, it's always useful as a relative metric; open up another view that has proven it's acceptability in the field, and compare yours to it.  Refresh (⌘-R) a few times to get a sense of the average layout time.

#### Stats View

The stats view at the upper left of the screen shows live, real-time performance stats:

![image alt text](http://imageshack.com/a/img923/8000/mbEElj.png)

The text will turn **yellow** or **red** if either texture usage or frame rate are unacceptable.  The offending number will have an exclamation point after it.

The values are:

Stat | Meaning | Yellow | Red
-------- | -------- | -------- | --------
FPS | Frame rate (frames per second) | <50 | <40
MEM | Memory Usage |  | 
DRW | Number of Draw Calls |  | 
SPI | Number of Spine Instances |  | 
SPB | Number of Spine Bones |  | 
PAR | Number of Particle Emitters |  | 
PAS | Number of Particles |  | 
MPx | Video Memory Usage (Megapixels) | >40 | >50


Here's an example with both FPS and MPx exclaiming their displeasure:

![image alt text](http://imageshack.com/a/img923/5987/xLsAMz.png)

For generic dialogs using all "common" resources, texture memory (measured in mega-pixels) is not going to be an issue.  But for games (slot machine themes, etc.) where the art can vary a lot, you must keep an eye on your texture memory usage.`

### Delaying Layout Processing

Some scenes or dialogs can become quite complex and start to take too long before they appear.  To address this, use the **"delayLayout"** property to delay the creation and layout of a control and all of it's children.

Some considerations when delaying controls:

* The controls that are delayed will not exist.  This means that calls to getControl to set things like visibility or play an animation won't work, and will result in a null exception.  Once the delayed controls are created, then they will be available through getControl or getControlFromGroup, etc.
* Controls that don't have a declared width and height may not center properly if creation is delayed.  For example, a layout group without a declared width and height will usually get its dimensions from its children.  But, if layout is delayed, the derived width and height of children will be zero.

#### Delay Layout Indefinitely

If the code will decide when a part of the layout needs creating, then specify -1 for the value of "delayLayout".  This has almost the same effect as "includeInLayout": false but with the one difference that the code can later on ask for those controls to be created.

The ViewLayout class has a public function createDelayedControls which takes a control id and an optional signal to dispatch when layout is complete.

#### Delay Layout for a Certain Number of Frames

To simply stagger the creation of parts of a layout, specify a positive integer for "delayLayout".  For example, "delayLayout": 1 will create the controls immediately after the main view layout is complete.

## The "animation" Section

You can define Tween animations for use in your layout view or mediator class.  See this document on [BCG Animation](https://docs.google.com/a/beecavegames.com/document/d/1vg1mlt3tXZDEUhQFIZG5LobuO9-m0-b7yQCka1jtuyI/edit?usp=sharing) and the AnimationManager class for details.

For example, the following defines a tween named "move_right".  You can play any animation against any target object by calling the play function in your code.

	"animations": {
		"move_right": {
			"_type": "com.greensock.TimelineLite",
			"tweens": [
				{
					"_type": "com.greensock.TweenLite",
					"duration": 0.5,
					"alpha": 1.0,
					"x": "50"
				}
			]
		}
	}

## The "assets" Section

The "assets" section lets you declare textures, sounds, and other resources that need to be loaded before this layout is created and shown.  The "assets" section supports two formats; a legacy array format, and a newer named resource format.

#### Older Array Format

The older array format is an array of objects that can declare "textureId", "fontId", etc. as if they were an array of controls.

	"assets": [	
		{
			"textureId": "BartonCreekLocationButtonGrid/LocationButton"
		}
	]

#### Newer Object Format

The newer format lets you declare a short resource name and a url.  The value of the "asset" property determines whether addTextureAtlas is called, or addResource is called in code.  This section can be used to completely eliminate the need to call these functions in a custom registerResources function in the view class.

	"assets": {
		"Background": {
			"asset": "textureAtlas",
			"url": "images2/SlotThemes/CarnivalInRio/Slots_CarnivalInRio_Background.jxr"
		},
		"UI": {
			"asset": "textureAtlas",
			"url": "images2/SlotThemes/CarnivalInRio/Slots_CarnivalInRio_UI.jxr"
		},
		"GameSoundBundle": {
			"asset": "resource",
			"url": "sounds/bundles/Game.amf",
			"type": "resources.resourceTypes.SoundBundleResource"
		}
	}

#### Un-Referencing Assets

Sometimes, layout files are extended and textures, bitmaps, or other resources that are referenced in the base layout are no longer used.  If these assets do not exist, they can cause the view to never load.  In this case it's necessary to explicitly clear out the use of a resource using the "assets" list.  Add an entry to the "assets" section for the resource that's no longer used, and set its "asset" field to null.

	"images2/Foo/Bar/OldTexture.jxr": {
		"asset": null,
		"url": "images2/Foo/Bar/OldTexture.jxr"
	},

## The "data" Section

The "data" section of the layout JSON file is used to declare arbitrary data for use by the view or mediator behavior.  The “data” section is an map of id to data.  Anything can be instantiated here, given that it at least has a “_type” field.

For example:

	"data": {
		"seatPos": {
			"_type":"dataModel.settings.SeatPositions",
			"x0":512,
			"y0":200,
			"x1":844,
			"y1":246
		}
	}

## Layout Processing

Processing the layout JSON files to create controls, skin, and position is divided into phases that take place over several frames.  The phases allow for Starling and Feathers to measure their correct sizes based on fonts and textures.  All the processing takes place in the class ViewLayout.  _(This section is somewhat out of date)_

### Step 1 - Load and parse the JSON layout

The first function in the process is loadViewLayoutFromJson.  The first pre-processing of the JSON data occurs here, where all "extends" are processed to make a single layout data object.  Several private functions are called to parse different sections of the layout data, including creating "controls".  (Controls are not added to the stage yet.)  The layout data is then scanned for texture and other asset references and adds them to the view's resource bundle.

### Step 2 - Add controls to the stage

This step does not occur until all resources needed for the view are loaded.  The ViewLayout's function addControlsAsChildren is called by the view when it's ready.  Because view's may include other views' there's a signal used to let all of them know when they're *all* done adding their controls to the stage, and ready for the next step.

### Step 3 - Skinning: assign textures to controls

ViewLayout function layoutPhase0

A pass is made over all controls to assign their various texture fields.  This is done first to assure that all controls have had a chance to measure their new dimensions based on the textures used.

### Step 4 - First layout pass

ViewLayout function layoutPhase1

The core positionAndSizeControl function is called for each control in the order they're declared in JSON.  All magic fields like "scale", and percentage-based value processing happens in this function.  For this phase, the processRelatives parameter is set to **false**, for the next phase it's set to **true**.  The processRelatives flag allows explicit widths and heights to be set in this phase, and percentage widths and heights in the next.

One frame is let pass before the second pass.  This is to allow Starling and Features to measure all display objects invalidated by this pass.

### Step 5 - Second layout pass

ViewLayout function layoutPhase2

The positionAndSizeControl function is called again, but this time with processRelatives parameter is set to **true**.  A lot of redundant work is done here, but it allows relative positioning and referencing other controls declared anywhere in the layout to give correct results.

One frame is let pass before the next pass.  This is to allow Starling and Features to measure all display objects invalidated by this pass.

### Step 6 - Final layout pass

Lastly, all LayoutGroup controls are invalidated.  LayoutGroup controls can set the positions of it's children, so they need one last chance to assess the final dimensions of all children and adjust their positions accordingly.

The layoutComplete signal is dispatched, letting the view proceed.

## Extends, Styles, and Overrides Processing

### Process Extends

Combine all the extended layouts, recursively, into one single layout data object.

All sections are merged, with the current layout taking priority (overwriting) extended layouts.

### Parse Styles

All data declared in the "styles" section is put into a Dictionary of style data objects.

Any "style" references are exploded, so that no data object "style" references remain.

Any "overrides" are processed by looking up each "id" in the override section and overwriting any properties.

Within a style, ids need not be unique.

### Process Styles

Recursively descend through the root level "controls" array and any "children" arrays and apply any "style" references and "overrides".

The resulting "controls" array will have no "style" or "override" entries in any control.

Ids declared within styles will have the id of the control pre-pended in order to preserve uniqueness.

### Create Controls

All data in "controls" will now be ready to use without any more "style" references or "overrides".

