package otlib.components
{
    import mx.core.IVisualElement;
    import spark.components.supportClasses.GroupBase;
    import spark.layouts.supportClasses.LayoutBase;

    /** Centers a preview when it fits and keeps overflowing content at the origin. */
    public class PreviewLayout extends LayoutBase
    {
        override public function measure():void
        {
            var group:GroupBase = target;
            if (!group) return;
            var preview:IVisualElement = getPreview();
            group.measuredWidth = preview ? preview.getPreferredBoundsWidth() : 0;
            group.measuredHeight = preview ? preview.getPreferredBoundsHeight() : 0;
            // The viewport may be smaller than the sprite; scrolling handles overflow.
            group.measuredMinWidth = group.measuredMinHeight = 0;
        }

        override public function updateDisplayList(width:Number, height:Number):void
        {
            var group:GroupBase = target;
            if (!group) return;
            var preview:IVisualElement = getPreview();
            if (!preview)
            {
                group.setContentSize(width, height);
                return;
            }

            preview.setLayoutBoundsSize(NaN, NaN);
            var previewWidth:Number = preview.getLayoutBoundsWidth();
            var previewHeight:Number = preview.getLayoutBoundsHeight();
            preview.setLayoutBoundsPosition(
                Math.max(0, Math.floor((width - previewWidth) / 2)),
                Math.max(0, Math.floor((height - previewHeight) / 2)));
            // Negative centered coordinates make BasicLayout under-report content
            // extents. Auto scrollbars then alternate forever near the sprite size.
            group.setContentSize(Math.ceil(Math.max(width, previewWidth)),
                    Math.ceil(Math.max(height, previewHeight)));
        }

        private function getPreview():IVisualElement
        {
            if (!target || target.numElements == 0) return null;
            var preview:IVisualElement = target.getElementAt(0);
            return preview.includeInLayout ? preview : null;
        }
    }
}
