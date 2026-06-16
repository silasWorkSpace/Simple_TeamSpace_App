import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:last_project_client/controllers/task_controller.dart';
import 'package:last_project_client/controllers/auth_controller.dart';
import 'package:last_project_client/controllers/user_controller.dart';
import 'package:last_project_client/models/task_model.dart';
import 'package:intl/intl.dart';
import 'package:last_project_client/views/tasks/task_edit_dialog.dart';

class KanbanTab extends StatelessWidget {
  const KanbanTab({super.key});

  void _showEditTaskDialog(BuildContext context, TaskModel task) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => TaskEditDialog(task: task),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TaskController>(
      builder: (context, taskController, child) {
        if (taskController.isLoading && taskController.tasks.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          children: [
            if (taskController.errorMessage != null)
              Container(
                color: Colors.red.shade100,
                padding: const EdgeInsets.all(8),
                width: double.infinity,
                child: Text(
                  taskController.errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildColumn(context, "TODO", taskController.todoTasks, Colors.blueGrey, taskController),
                    const SizedBox(width: 8),
                    _buildColumn(context, "DOING", taskController.doingTasks, Colors.blue, taskController),
                    const SizedBox(width: 8),
                    _buildColumn(context, "DONE", taskController.doneTasks, Colors.green, taskController),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildColumn(BuildContext context, String columnStatus, List<TaskModel> tasks, Color color, TaskController controller) {
    return Expanded(
      child: DragTarget<TaskModel>(
        onWillAccept: (task) => task != null && task.status != columnStatus && controller.movingTaskId == null,
        onAccept: (task) => controller.updateTaskStatus(task.id, columnStatus),
        builder: (context, candidateData, rejectedData) {
          final isOver = candidateData.isNotEmpty;
          
          return Container(
            decoration: BoxDecoration(
              color: isOver ? color.withOpacity(0.15) : color.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isOver ? color : color.withOpacity(0.2),
                width: isOver ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        columnStatus,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color.darken(),
                        ),
                      ),
                      CircleAvatar(
                        radius: 10,
                        backgroundColor: color,
                        child: Text(
                          tasks.length.toString(),
                          style: const TextStyle(fontSize: 10, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      return TaskCard(
                        task: tasks[index],
                        onTap: () => _showEditTaskDialog(context, tasks[index]),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class TaskCard extends StatelessWidget {
  final TaskModel task;
  final VoidCallback? onTap;

  const TaskCard({super.key, required this.task, this.onTap});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, HH:mm');
    final userController = context.watch<UserController>();
    final authController = context.watch<AuthController>();
    final taskController = context.watch<TaskController>();
    
    final currentUserId = authController.currentUser?.id;
    final bool canDrag = task.creatorId == currentUserId || task.assigneeId == currentUserId;
    final bool isMoving = taskController.movingTaskId == task.id;

    Widget cardContent = Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isMoving ? 0 : 1,
      color: isMoving ? Colors.grey.shade50 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isMoving ? BorderSide(color: Colors.grey.shade300) : BorderSide.none,
      ),
      child: InkWell(
        onTap: isMoving ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Opacity(
            opacity: isMoving ? 0.5 : 1.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        task.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (isMoving)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (task.assigneeId != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          userController.getName(task.assigneeId!),
                          style: TextStyle(fontSize: 10, color: Colors.blue.shade800),
                        ),
                      ),
                  ],
                ),
                if (task.description != null && task.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    task.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      dateFormat.format(task.updatedAt),
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    ),
                    Text(
                      "By ${userController.getName(task.creatorId)}",
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!canDrag || isMoving) {
      return cardContent;
    }

    return LongPressDraggable<TaskModel>(
      data: task,
      axis: null,
      feedback: SizedBox(
        width: MediaQuery.of(context).size.width * 0.25, // Approx column width
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: cardContent,
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: cardContent,
      ),
      child: cardContent,
    );
  }
}

extension ColorExtension on Color {
  Color darken([double amount = .1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
}
