package ui.controls
{
	import com.greensock.core.Animation;
	
	import flash.geom.Point;
	import flash.geom.Rectangle;
	import flash.text.TextFormatAlign;
	import flash.utils.setTimeout;
	
	import animations.AnimationTween;
	
	import feathers.controls.Label;
	import feathers.core.ITextRenderer;
	import feathers.text.BitmapFontTextFormat;
	
	import starling.display.Image;
	import starling.text.BitmapFont;
	
	import ui.controls.text.AnimatedBitmapFontTextRenderer;
	
	public class AnimatedLabel extends Label
	{
		public function AnimatedLabel() {
			super();
			touchable = false;
			textRendererProperties.snapToPixels = false;
		}

		// Properties that need to be set before added to stage
		private var _font:BitmapFont;
		public var color:uint = 0xffffff;
		public var size:Number;
		public var letterSpacing:Number = 0;
		public var align:String = TextFormatAlign.LEFT;
		//public var valign:String = BitmapFontTextFormat.VERTICAL_ALIGN_TOP;
		public var isKerningEnabled:Boolean = true;
		private var _textRenderer:AnimatedBitmapFontTextRenderer;
		private var _inAnimationTemplate:AnimationTween;
		private var _inStagger:Number;
		private var _outAnimationTemplate:AnimationTween;
		private var _outStagger:Number;
		private var _idleAnimationTemplate:AnimationTween;
		private var _idleStagger:Number;
		private var _clip:Boolean;
		private var _shrinkToFit:Boolean;

		public function get clip():Boolean { return _clip; }
		public function set clip(value:Boolean):void {
			_clip = value;
			this.invalidate(INVALIDATION_FLAG_SIZE);
		}

		public function get textRenderer():AnimatedBitmapFontTextRenderer { return _textRenderer; }
		public function set textRenderer(value:AnimatedBitmapFontTextRenderer):void {
			_textRenderer = value;
			if (textRenderer) {
				if (_inAnimationTemplate) {
					_textRenderer.inAnimationFactory = myInAnimationFactory;
					_textRenderer.inStagger = _inStagger;
				} else {
					_textRenderer.inAnimationFactory = null;
				}
				if (_outAnimationTemplate) {
					_textRenderer.outAnimationFactory = myOutAnimationFactory;
					_textRenderer.outStagger = _outStagger;
				} else {
					_textRenderer.outAnimationFactory = null;
				}
				if (_idleAnimationTemplate) {
					_textRenderer.idleAnimationFactory = myIdleAnimationFactory;
					_textRenderer.idleStagger = _idleStagger;
				} else {
					_textRenderer.idleAnimationFactory = null;
				}
			}
			if (clip) {
				_textRenderer.clipRect = new Rectangle(0, 0, width, height);
			}
		}

		public function get outAnimationTemplate():AnimationTween { return _outAnimationTemplate; }
		public function set outAnimationTemplate(value:AnimationTween):void {
			_outAnimationTemplate = value;
			if (textRenderer) {
				if (_outAnimationTemplate) {
					textRenderer.outAnimationFactory = myOutAnimationFactory;
				} else {
					textRenderer.outAnimationFactory = null;
				}
			}
		}
		
		public function get outStagger():Number { return _outStagger; }
		public function set outStagger(value:Number):void {
			_outStagger = value;
			if (textRenderer) {
				textRenderer.outStagger = value;
			}
		}
		
		public function get idleAnimationTemplate():AnimationTween { return _idleAnimationTemplate; }
		public function set idleAnimationTemplate(value:AnimationTween):void {
			_idleAnimationTemplate = value;
			if (textRenderer) {
				if (_idleAnimationTemplate) {
					textRenderer.idleAnimationFactory = myIdleAnimationFactory;
				} else {
					textRenderer.idleAnimationFactory = null;
				}
			}
		}
		
		public function get idleStagger():Number { return _idleStagger; }
		public function set idleStagger(value:Number):void {
			_idleStagger = value;
			if (textRenderer) {
				textRenderer.idleStagger = value;
			}
		}
		
		public function get inAnimationTemplate():AnimationTween { return _inAnimationTemplate; }
		public function set inAnimationTemplate(value:AnimationTween):void {
			_inAnimationTemplate = value;
			if (textRenderer) {
				if (_inAnimationTemplate) {
					textRenderer.inAnimationFactory = myInAnimationFactory;
				} else {
					textRenderer.inAnimationFactory = null;
				}
			}
		}
		
		public function get inStagger():Number { return _inStagger; }
		public function set inStagger(value:Number):void {
			_inStagger = value;
			if (textRenderer) {
				textRenderer.inStagger = value;
			}
		}
		
		public function get shrinkToFit():Boolean { return _shrinkToFit; }
		public function set shrinkToFit( value:Boolean ) : void {
			_shrinkToFit = value;
			autoSizeIfNeeded();
		}
		
		public function get font():BitmapFont { return _font; }

		public function set font(value:BitmapFont):void {
			_font = value;
			setTimeout( initialize, 0 );
		}

		override protected function initialize():void {
			super.initialize();
			textRendererFactory = myTextRendererFactory;
			if (font) {
				textRendererProperties.textFormat = new BitmapFontTextFormat( font, size, color, align );
			}
		}
		
		protected function myOutAnimationFactory(img:Image):Animation {
			var anim:Animation = _outAnimationTemplate.createTween( img );
			return anim;
		}
		
		protected function myIdleAnimationFactory(img:Image):Animation {
			var anim:Animation = _idleAnimationTemplate.createTween( img );
			return anim;
		}
		
		protected function myInAnimationFactory(img:Image):Animation {
			var anim:Animation = _inAnimationTemplate.createTween( img );
			return anim;
		}
		
		override protected function setSizeInternal(width:Number, height:Number, canInvalidate:Boolean):Boolean {
			var result:Boolean = super.setSizeInternal( width, height, canInvalidate );
			if (clip && textRenderer) {
				textRenderer.clipRect = new Rectangle(0, 0, width, height);
			}
			return result;
		}
		
		public function myTextRendererFactory():ITextRenderer {
			if (textRenderer == null) {
				textRenderer = new AnimatedBitmapFontTextRenderer();
			}
			return textRenderer;
		}

		override public function set text(value:String):void
		{
//			if(this._text == value || (!value && this._text == " "))
//			{
//				return;
//			}
			if (!value)
			{
				value = " "; 	// Need at least some incoming character so we don't get invisible'd
			}
			this._text = value;
			this.invalidate(INVALIDATION_FLAG_DATA);
		}

		protected static const _workPoint:Point = new Point();
		
		override protected function autoSizeIfNeeded():Boolean {
			var result:Boolean = false;
			
			if ( textRenderer && textRenderer.textFormat && this.text ) {
				if ( shrinkToFit ) {

					var textSize:Number = textRenderer.textFormat.font.size;
					
					textRenderer.textFormat.size = Number.NaN;
					textRenderer.measureText( _workPoint );
					while ( _workPoint.x * this.scaleX > this.explicitWidth && textSize > 4 ) {
						textSize -= 1;
						textRenderer.textFormat.size = textSize;
						textRenderer.measureText( _workPoint );
						result = true;
					}
				}
				else if ( !isNaN(textRenderer.textFormat.size ) ) {
					textRenderer.textFormat.size = Number.NaN;
					result = true;
				}
			}
			return result;
		}
	}
}