package viewLayout {
	
	import flash.geom.Rectangle;
	
	import org.as3commons.reflect.Type;
	
	import starling.display.DisplayObject;
	
	import ui.controls.LayoutGroup;
	
	public class ConfigurableControl {
		
		public var controlType:Type;
		public var config:Object;
		public var layer:String;
		public var parent:ConfigurableControl;
		public var controlIsLayoutGroup:Boolean;
		public var originalNumChildren:int=0;
		public var nesting:int = 0;
		public var depth:int = 0;
		public var order:int = 0;
		public var bounds:Rectangle;
		private var _totalChildWidthPercentage:Number = 0;
		private var _totalChildHeightPercentage:Number = 0;
		private var _totalChildWidthConcrete:Number = 0;
		private var _totalChildHeightConcrete:Number = 0;
		public var finalData:Object = {};
		public var id:String;
		public var direction:String;
		public var control:starling.display.DisplayObject;
		
		public function ConfigurableControl( data:Object, layer:String ) {
			this.config = data;
			this.layer = layer;
		}
		
		public function dispose():void {
			control = null;
		}
		
		public function get totalChildHeightConcrete():Number { return _totalChildHeightConcrete; }
		public function set totalChildHeightConcrete(value:Number):void {
			if (!controlIsLayoutGroup || direction == LayoutGroup.DIRECTION_VERTICAL) {
				_totalChildHeightConcrete = value;
			}
		}

		public function get totalChildWidthConcrete():Number { return _totalChildWidthConcrete; }
		public function set totalChildWidthConcrete(value:Number):void
		{
			if (!controlIsLayoutGroup || direction == LayoutGroup.DIRECTION_HORIZONTAL) {
				_totalChildWidthConcrete = value;
			}
		}

		public function get totalChildHeightPercentage():Number { return _totalChildHeightPercentage; }
		public function set totalChildHeightPercentage(value:Number):void {
			if (!controlIsLayoutGroup || direction == LayoutGroup.DIRECTION_VERTICAL) {
				_totalChildHeightPercentage = value;
			}
		}

		public function get totalChildWidthPercentage():Number { return _totalChildWidthPercentage; }
		public function set totalChildWidthPercentage(value:Number):void {
			if (!controlIsLayoutGroup || direction == LayoutGroup.DIRECTION_HORIZONTAL) {
				_totalChildWidthPercentage = value;
			}
		}
		
		public function setProperty( control:DisplayObject, name:String, value:* ): void {
			finalData[name] = value;
			control[name] = value;
		}

		public function getTextureIds( textureIds:Vector.<String> ): void {
			for ( var prop:String in config ) {
				if ( prop.search( /[Tt]extureId/ ) != -1 ) {
					textureIds.push( config[prop] );
				}
			}
		}
		
		// Call after setting control
		public function initialize(id:String, control:DisplayObject, parent:ConfigurableControl, nesting:int, order:int, controlType:Type, depth:int):void {
			var controlAsLayoutGroup:LayoutGroup = control as LayoutGroup;
			this.controlIsLayoutGroup = (controlAsLayoutGroup != null);
			this.direction = this.controlIsLayoutGroup ? controlAsLayoutGroup.direction : LayoutGroup.DIRECTION_NONE;
			this.parent = parent;
			this.nesting = nesting;
			this.order = order;
			this.id = id;
			this.depth = depth;
			this.controlType = controlType;
			this.finalData["name"] = control.name;
		}
	}
}