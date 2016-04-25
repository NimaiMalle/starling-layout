package ui.controls
{
	import com.greensock.TweenLite;
	import com.greensock.core.Animation;
	import com.greensock.easing.Linear;
	
	import flash.utils.clearTimeout;
	import flash.utils.setTimeout;
	
	import signals.BaseSignal;
	
	import starling.display.Image;
	
	import ui.controls.text.AnimatedBitmapFontTextRenderer;
	
	import util.LocUtil;

	public class OdometerLabel extends AnimatedLabel
	{
		public var onTargetReached:BaseSignal = new BaseSignal();
		
		public function OdometerLabel() {
			super();
			clip = true;
		}

		public function get step():Number { return _step; }
		public function set step(value:Number):void {
			if ( value < 0 ) {
				_step = value > -1.0 ? -1.0 : value;
			} else {
				_step = value < 1.0 ? 1.0 : value;
			}
			_needsConfigure = true;
		}

		public function get digitTransitionTime():Number { return _digitTransitionTime; }
		public function set digitTransitionTime(value:Number):void {
			_digitTransitionTime = value;
			_needsConfigure = true;
		}

		public function get timeToReachTarget():Number { return _timeToReachTarget; }
		public function set timeToReachTarget(value:Number):void {
			_timeToReachTarget = value;
			_needsConfigure = true;
		}

		public function get paused():Boolean { return _paused; }
		public function set paused(value:Boolean):void {
			if (_paused != value) {
				_paused = value;
				if (!_paused) {
					doStep();
				}
			}
		}

		public var formatFunction:Function = defaultFormatter;

		private var _paused:Boolean;
		private var _timeToReachTarget:Number;
		private var _digitTransitionTime:Number;
		private var _step:Number;

		private var _targetValue:Number;
		private var _value:Number = 0;
		private const MIN_TRANSITION_TIME:Number = 1/30;

		private const DEFAULT_TIME_TO_REACH_TARGET:Number = 30.0;
		private const DEFAULT_DIGIT_TRANSITION_TIME:Number = 0.75;
		private const DEFAULT_STEP:Number = 1.0;

		private const DERIVE_AUTO:int = 0;
		private const DERIVE_TIME_TO_REACH_TARGET:int = 1;
		private const DERIVE_DIGIT_TRANSITION_TIME:int = 2;
		private const DERIVE_STEP:int = 3;
		private const CHECK_START_TIME:int = 250;

		private var _deriveMode:int = DERIVE_AUTO;
		private var _needsConfigure:Boolean;
		private var _setTargetNextFrame:uint;
		private var _checkStartTimer:uint;

		/**
		 * Immediately transition to the new value.
		 */
		public function set value(amount:Number):void {
			if (_value != amount) {
				_value = amount;
				text = formatFunction( amount );
				doStep();
			}
		}

		public function get value():Number {
			return _value;
		}

		public function configureTime( timeToReachTarget:Number, digitTransitionTime:Number ):void {
			_deriveMode = DERIVE_STEP;
			_timeToReachTarget = timeToReachTarget;
			_digitTransitionTime = digitTransitionTime;
			_step = NaN;
			_needsConfigure = true;
		}

		public function configureStep( step:Number, digitTransitionTime:Number ):void {
			_deriveMode = DERIVE_TIME_TO_REACH_TARGET;
			timeToReachTarget = NaN;
			_digitTransitionTime = digitTransitionTime;
			_step = step;
			_needsConfigure = true;
		}

		public function configureTransition( step:Number, timeToReachTarget:Number ):void {
			_deriveMode = DERIVE_DIGIT_TRANSITION_TIME;
			_timeToReachTarget = timeToReachTarget;
			_digitTransitionTime = NaN;
			_step = step;
			_needsConfigure = true;
		}

		private function configure(target:Number):void {
			if (target == target) {
				var delta:Number = target - _value;
				switch (_deriveMode) {
					case DERIVE_AUTO:
						if (_timeToReachTarget != _timeToReachTarget) {
							deriveTimeToReachTarget(delta);
						} else if (_digitTransitionTime != _digitTransitionTime) {
							deriveDigitTransitionTime(delta);
						} else {
							deriveStep(delta);
						}
						break;
					case DERIVE_TIME_TO_REACH_TARGET:
						deriveTimeToReachTarget(delta);
						break;
					case DERIVE_DIGIT_TRANSITION_TIME:
						deriveDigitTransitionTime(delta);
						break;
					case DERIVE_STEP:
						deriveStep(delta);
						break;
				}
			}
			_needsConfigure = false;
		}

		private function deriveTimeToReachTarget(delta:Number):void {
			if (digitTransitionTime != digitTransitionTime) {
				digitTransitionTime = DEFAULT_DIGIT_TRANSITION_TIME;
			}
			if (step != step) {
				step = DEFAULT_STEP;
			}
			timeToReachTarget = digitTransitionTime * (delta / step)
		}

		private function deriveDigitTransitionTime(delta:Number):void {
			if (timeToReachTarget != timeToReachTarget) {
				timeToReachTarget = DEFAULT_TIME_TO_REACH_TARGET;
			}
			if (step != step) {
				step = DEFAULT_STEP;
			}
			digitTransitionTime = timeToReachTarget * (step / delta)
		}

		private function deriveStep(delta:Number):void {
			if (digitTransitionTime != digitTransitionTime) {
				digitTransitionTime = DEFAULT_DIGIT_TRANSITION_TIME;
			}
			if (timeToReachTarget != timeToReachTarget) {
				timeToReachTarget = DEFAULT_TIME_TO_REACH_TARGET;
			}
			step = delta * (digitTransitionTime / timeToReachTarget);
		}

		public function forceValue(amount:Number):void {
			if (textRenderer) {
				var oldPaused:Boolean = _paused;
				_paused = true;
				// Set the value
				_value = amount;
				_targetValue = amount;
				// Set the label's text field
				text = formatFunction( amount );
				refreshTextRendererData();
				if (_checkStartTimer != 0) {
					clearTimeout(_checkStartTimer);
					_checkStartTimer = 0;
				}
				// Clear the invalidation flag, since we're going to force draw next
				delete this._invalidationFlags[INVALIDATION_FLAG_DATA];
				// Use forceDraw to skip any animation and create the character sprites in their final positions
				textRenderer.forceDraw();

				_paused = oldPaused;
			}
		}

		/**
		 * Starts the odometer rolling towards a target value.
		 * Must set other configuration parameters first, like "step", "timeToReachTarget", and "digitTransitionTime"
		 */
		public function set targetValue(amount:Number):void {
			if (_targetValue != amount) {
				_targetValue = amount;
				if ( _setTargetNextFrame == 0 ) {
					_setTargetNextFrame = setTimeout( setTargetValueInternal, 0);
				}
			}
		}

		/**
		 * Kick things off on the next frame to accomodate setting any other configuration parameters this frame.
		 */
		private function setTargetValueInternal():void {
			_setTargetNextFrame = 0;
			configure(_targetValue);
			doStep();
		}

		private function checkReady():void {
			if (textRenderer == null) {
				_checkStartTimer = setTimeout( checkReady, CHECK_START_TIME );
			} else {
				_checkStartTimer = 0;
				doStep();
			}
		}

		private function doStep():void {
			if (_paused) {
				return;
			}

			if (textRenderer == null) {
				if (_checkStartTimer == 0) {
					_checkStartTimer = setTimeout( checkReady, CHECK_START_TIME );
				}
				return;
			} else {
				if (_checkStartTimer != 0) {
					clearTimeout(_checkStartTimer);
					_checkStartTimer = 0;
				}
			}

			if (_targetValue == _targetValue && textRenderer.isAnimating == false) {
				if (_step < 0) {
					if (_value + _step < _targetValue) {
						_value = _targetValue;
						_targetValue = NaN;
						onTargetReached.dispatch();
					} else {
						_value = _value + _step;
					}
				} else {
					if (_value + _step > _targetValue) {
						_value = _targetValue;
						_targetValue = NaN;
						onTargetReached.dispatch();
					} else {
						_value = _value + _step;
					}
				}
				if ( isNaN(_value) ) {
					_value = _targetValue;	// bad case, just snap to target for now
				}
				text = formatFunction( _value );
			}
		}

		public function get targetValue():Number {
			return _targetValue;
		}

		protected function onOutComplete():void {
			doStep();
		}

		override protected function myOutAnimationFactory(img:Image):Animation {
			if (digitTransitionTime==digitTransitionTime && digitTransitionTime>0) {
				return TweenLite.to( img, digitTransitionTime, {"y": String(height * 1.05), "ease": Linear.easeNone} );
			} else {
				return null;
			}
		}

		override protected function myInAnimationFactory(img:Image):Animation {
			if (digitTransitionTime==digitTransitionTime && digitTransitionTime>0) {
				return TweenLite.from( img, digitTransitionTime, {"y": String(-height * 1.05), "ease": Linear.easeNone} );
			} else {
				return null;
			}
		}

		private function defaultFormatter( amount:Number ):String {
			return LocUtil.numberToCurrency( amount, false, false, -1, 0 );
		}

		override public function set textRenderer(value:AnimatedBitmapFontTextRenderer):void {
			super.textRenderer = value;
			value.inAnimationFactory = myInAnimationFactory;
			value.outAnimationFactory = myOutAnimationFactory;
			value.animateCompleteCallback = onOutComplete;
			value.skipSameCharacter = true;
		}

	}
}