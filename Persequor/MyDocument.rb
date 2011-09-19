#
#  MyDocument.rb
#  Persequor
#
#  Created by Sven A. Schmidt on 18.09.11.
#  Copyright 2011 abstracture GmbH & Co. KG. All rights reserved.
#

require 'trac4r/trac'


class MyDocument < NSPersistentDocument
  attr_accessor :array_controller
  attr_accessor :is_loading
  attr_accessor :predicate_editor
  attr_accessor :previous_row_count
  attr_accessor :progress_bar
  attr_accessor :toolbar_view
  attr_accessor :queue
  attr_accessor :refresh_button
  attr_accessor :table_view

  def init
  	super
  	if (self != nil)
      @queue = Dispatch::Queue.new('de.abstracture.presequor')
  	end
    self
  end


  def windowNibName
    # Override returning the nib file name of the document
    # If you need to use a subclass of NSWindowController or if your document supports multiple NSWindowControllers, you should remove this method and override -makeWindowControllers instead.
    "MyDocument"
  end


  def windowControllerDidLoadNib(aController)
    super
    setup_predicate_editor
  end


  # helpers
  
  def defaults(key)
    defaults = NSUserDefaults.standardUserDefaults
    defaults.objectForKey(key)
  end


  def setup_predicate_editor
    @predicate_editor.enclosingScrollView.setHasVerticalScroller(false)
    @previous_row_count = 2
    @predicate_editor.addRow(self)
    display_value = @predicate_editor.displayValuesForRow(1).lastObject
    if display_value.isKindOfClass(NSControl)
      self.windowForSheet.makeFirstResponder(display_value)
    end
  end

  
  # actions
  
  
  def predicateEditorChanged(sender)
    predicate = @predicate_editor.objectValue
    p predicate.predicateFormat
    @array_controller.setFilterPredicate(predicate)
    
    # resize window as needed
    new_row_count = @predicate_editor.numberOfRows
    
    if new_row_count == previous_row_count
      return
    end
    
    table_scroll_view = @table_view.enclosingScrollView
    old_outline_mask = table_scroll_view.autoresizingMask
    
    predicate_editor_scroll_view = @predicate_editor.enclosingScrollView
    old_predicate_editor_mask = predicate_editor_scroll_view.autoresizingMask
    
    table_scroll_view.setAutoresizingMask(NSViewWidthSizable | NSViewMaxYMargin)
    predicate_editor_scroll_view.setAutoresizingMask(NSViewWidthSizable | NSViewHeightSizable)
    
    growing = new_row_count > previous_row_count
    
    heightDiff = @predicate_editor.rowHeight \
      * (new_row_count - @previous_row_count)
    heightDiff = heightDiff.abs
    
    sizeChange = @predicate_editor.convertSize([0, heightDiff], toView:nil)
    
    # offset toolbar_view
    frame = @toolbar_view.frame
    @toolbar_view.setFrameOrigin(
      [frame.origin.x,
       frame.origin.y \
       - @predicate_editor.rowHeight * (new_row_count - previous_row_count)]
    )
    
    # change window frame size
    windowFrame = self.windowForSheet.frame
    windowFrame.size.height += growing ? sizeChange.height : -sizeChange.height
    windowFrame.origin.y -= growing ? sizeChange.height : -sizeChange.height
    self.windowForSheet.setFrame(windowFrame, display:true, animate:false)
    
    table_scroll_view.setAutoresizingMask(old_outline_mask)
    predicate_editor_scroll_view.setAutoresizingMask(old_predicate_editor_mask)
    
    @previous_row_count = new_row_count
  end
  
  
  def start_show_progress(max_count)
    Dispatch::Queue.main.async do
      if max_count > 0
        @progress_bar.setIndeterminate(false)
        @progress_bar.setDoubleValue(0)
        @progress_bar.setMaxValue(max_count)
      else
        @progress_bar.setIndeterminate(true)
        @progress_bar.startAnimation(self)
      end
      @progress_bar.hidden = false
      @refresh_button.enabled = false
    end
  end
  
  
  def end_show_progress
    Dispatch::Queue.main.async do
      @progress_bar.hidden = true
      @refresh_button.enabled = true
    end
  end
  
  
  def load_tickets(trac, ids, n_queues=2)
    group = Dispatch::Group.new
    queues = []
    n_queues.times do |i|
      queues << Dispatch::Queue.new("de.abstracture.queue-#{i}")
    end

    ids.each do |id|
      queue_id = id % n_queues
      queues[queue_id].async(group) do
        t = trac.tickets.get(id)
        puts "loaded #{id} (queue: #{queue_id})"
        Dispatch::Queue.main.async do
          @progress_bar.incrementBy(1)
          @array_controller.addObject(t)
        end
      end
    end
    group.wait
  end
  
  
  def button_pressed(sender)
    puts 'loading tickets'
    @queue.async do
      @is_loading = true
      start_show_progress(0)

      # clear array
      Dispatch::Queue.main.async do
        count = @array_controller.arrangedObjects.size
        index_set = NSIndexSet.indexSetWithIndexesInRange([0, count])
        @array_controller.removeObjectsAtArrangedObjectIndexes(index_set)
      end
      
      username = defaults("username")
      trac = Trac.new(defaults("tracUrl"),
                      username,
                      defaults("password"))
#     filter = ["owner=#{username}", "status!=closed"]
      filter = ["status!=closed"]
      tickets = trac.tickets.filter(filter)
      
      start_show_progress(tickets.size)
      load_tickets(trac, tickets)
      
      end_show_progress
      @is_loading = false
    end
  end


  def clear_button_pressed(sender)
    count = @predicate_editor.numberOfRows
    while count > 1 do
      @predicate_editor.removeRowAtIndex(count-1)
      count -= 1
    end
  end

end

